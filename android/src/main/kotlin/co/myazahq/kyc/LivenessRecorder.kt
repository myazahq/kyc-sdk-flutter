package co.myazahq.kyc

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

/**
 * Owns the Android camera for the liveness step using a single CameraX session
 * with exactly two use cases — **Preview + ImageAnalysis** — which is broadly
 * supported (unlike Preview + ImageAnalysis + VideoCapture, which exceeds the
 * use-case cap on many devices and starves the analysis stream).
 *
 * Each ImageAnalysis frame is fanned out to BOTH:
 *   • ML Kit face detection → gesture signals streamed to Dart, and
 *   • a MediaCodec H.264 encoder → an MP4 that shows the gestures.
 *
 * Preview renders into a Flutter [TextureRegistry.SurfaceTextureEntry], so the
 * Dart side displays it with a `Texture` widget. This is Android-only and used
 * solely by the liveness screen; document/selfie capture keep using the Flutter
 * camera plugin.
 */
class LivenessRecorder(
  private val context: Context,
  private val textures: TextureRegistry,
  private val onFace: (Map<String, Any>?) -> Unit,
) : LifecycleOwner {

  private val tag = "KycLivenessRecorder"

  // Minimal lifecycle we drive ourselves (CameraX binds to it).
  private val lifecycleRegistry = LifecycleRegistry(this)
  override val lifecycle: Lifecycle get() = lifecycleRegistry

  private val analysisExecutor = Executors.newSingleThreadExecutor()
  private var cameraProvider: ProcessCameraProvider? = null

  private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
  val textureId: Long get() = textureEntry?.id() ?: -1

  private val detector: FaceDetector = FaceDetection.getClient(
    FaceDetectorOptions.Builder()
      .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
      .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
      .enableTracking()
      .setMinFaceSize(0.15f)
      .build(),
  )

  // Encoder state (guarded on the encoder thread).
  private var encoderThread: HandlerThread? = null
  private var encoderHandler: Handler? = null
  @Volatile private var encoder: LivenessVideoEncoder? = null
  @Volatile private var recording = false
  private var videoPath: String? = null

  @Volatile private var sensorRotation = 0
  @Volatile private var analyzing = false
  private var previewWidth = 0
  private var previewHeight = 0

  // Preview surface buffer size (landscape sensor dims) — reported to Dart so it
  // can rotate/scale the Texture into an upright, correctly-proportioned circle.
  @Volatile var previewBufferWidth = 0
  @Volatile var previewBufferHeight = 0
  val rotationDegrees: Int get() = sensorRotation

  // Latest NV21 frame, cached so the selfie still can be encoded from it.
  @Volatile private var lastNv21: ByteArray? = null
  @Volatile private var lastNv21Width = 0
  @Volatile private var lastNv21Height = 0

  /** Starts the camera + preview + analysis. [onReady] gets the texture id. */
  fun start(onReady: (Long) -> Unit, onError: (String) -> Unit) {
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
      try {
        cameraProvider = future.get()
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        bindUseCases()
        onReady(textureId)
      } catch (e: Exception) {
        Log.e(tag, "camera start failed", e)
        onError(e.message ?: "camera start failed")
      }
    }, androidx.core.content.ContextCompat.getMainExecutor(context))
  }

  private fun bindUseCases() {
    val provider = cameraProvider ?: return

    val entry = textures.createSurfaceTexture()
    textureEntry = entry
    val surfaceTexture = entry.surfaceTexture()

    val preview = Preview.Builder()
      .setTargetResolution(Size(720, 1280))
      .build()
    preview.setSurfaceProvider { request ->
      val res = request.resolution
      previewBufferWidth = res.width
      previewBufferHeight = res.height
      surfaceTexture.setDefaultBufferSize(res.width, res.height)
      val surface = Surface(surfaceTexture)
      request.provideSurface(
        surface,
        analysisExecutor,
        { surface.release() },
      )
    }

    val analysis = ImageAnalysis.Builder()
      .setTargetResolution(Size(720, 1280))
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
      .build()
    analysis.setAnalyzer(analysisExecutor) { proxy -> onFrame(proxy) }

    val selector = CameraSelector.DEFAULT_FRONT_CAMERA
    provider.unbindAll()
    val camera = provider.bindToLifecycle(this, selector, preview, analysis)
    sensorRotation = camera.cameraInfo.sensorRotationDegrees
    lifecycleRegistry.currentState = Lifecycle.State.RESUMED
  }

  private fun onFrame(proxy: ImageProxy) {
    val w = proxy.width
    val h = proxy.height
    previewWidth = w
    previewHeight = h

    // 1) Feed the encoder (if recording) on its own thread. The encoder is
    //    created lazily here, on the first frame, so its dimensions match the
    //    real frame size (the sensor delivers landscape WxH, e.g. 1280x720).
    if (recording) {
      try {
        val dest = ByteArray(Yuv.i420Size(w, h))
        Yuv.toI420(proxy, dest)
        val path = videoPath
        encoderHandler?.post {
          var enc = encoder
          if (enc == null && path != null) {
            try {
              // Rotation is baked in via the muxer orientation hint.
              enc = LivenessVideoEncoder(w, h, path, sensorRotation)
              enc.start()
              encoder = enc
            } catch (e: Exception) {
              Log.e(tag, "encoder start failed", e)
              return@post
            }
          }
          enc?.encodeI420(dest)
        }
      } catch (e: Exception) {
        Log.w(tag, "i420 convert failed: ${e.message}")
      }
    }

    // 2) Feed ML Kit. Guard against overlap (KEEP_ONLY_LATEST already drops, but
    //    detection is async so we gate with `analyzing`).
    if (analyzing) {
      proxy.close()
      return
    }
    analyzing = true
    try {
      val nv21 = Yuv.toNv21(proxy)
      // Cache the latest NV21 frame so the selfie still can be encoded from it
      // (the native recorder owns the camera, so the Flutter plugin can't take
      // the picture). Guarded by @Volatile; replaced each frame.
      lastNv21 = nv21
      lastNv21Width = w
      lastNv21Height = h
      val rotation = sensorRotation
      // Mean luminance (0–255) of the central frame region — shipped with the
      // face data so the Dart side can drive lighting guidance (the raw frame
      // never reaches Dart on this native-recorder path).
      val luma = meanLuma(nv21, w, h)
      val image = InputImage.fromByteArray(
        nv21, w, h, rotation, InputImage.IMAGE_FORMAT_NV21,
      )
      detector.process(image)
        .addOnSuccessListener { faces ->
          val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
          onFace(face?.let { toPayload(it, w, h, rotation, faces.size, luma) })
        }
        .addOnFailureListener { onFace(null) }
        .addOnCompleteListener {
          analyzing = false
          proxy.close()
        }
    } catch (e: Exception) {
      analyzing = false
      proxy.close()
    }
  }

  /** Begins recording the gesture clip to a temp MP4. The encoder itself is
   *  created lazily on the first analysis frame ([onFrame]) so its dimensions
   *  always match the real frame size. Creating it here would race the camera's
   *  first frame: `previewWidth/Height` are still 0 at this point, so the encoder
   *  would default to a transposed size (720×1280 vs the sensor's 1280×720),
   *  every `encodeI420` copy would throw, and the muxer would never start —
   *  yielding a 0-byte MP4. */
  fun startRecording() {
    if (recording) return
    val path = File(context.cacheDir, "kyc_liveness_${System.currentTimeMillis()}.mp4").absolutePath
    videoPath = path

    val thread = HandlerThread("kyc-liveness-encoder").also { it.start() }
    encoderThread = thread
    encoderHandler = Handler(thread.looper)
    // Frames now drive lazy encoder creation with their actual dimensions.
    recording = true
  }

  /** Stops recording and returns the MP4 path (or null). Blocks briefly. */
  fun stopRecording(): String? {
    if (!recording) return videoPath
    recording = false
    val handler = encoderHandler
    val thread = encoderThread
    val latch = java.util.concurrent.CountDownLatch(1)
    handler?.post {
      try { encoder?.stop() } catch (_: Exception) {}
      encoder = null
      latch.countDown()
    } ?: latch.countDown()
    try { latch.await(3, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Exception) {}
    thread?.quitSafely()
    encoderThread = null
    encoderHandler = null
    return videoPath
  }

  /**
   * Encodes the latest camera frame to a front-facing JPEG: rotates by the
   * sensor orientation so the face is upright, mirrors horizontally to match the
   * preview the user saw, and JPEG-compresses. Returns null if no frame yet.
   */
  fun captureStillJpeg(quality: Int = 90): ByteArray? {
    val nv21 = lastNv21 ?: return null
    val w = lastNv21Width
    val h = lastNv21Height
    if (w == 0 || h == 0) return null
    return try {
      val yuv = android.graphics.YuvImage(nv21, android.graphics.ImageFormat.NV21, w, h, null)
      val jpegStream = java.io.ByteArrayOutputStream()
      yuv.compressToJpeg(android.graphics.Rect(0, 0, w, h), 100, jpegStream)
      var bmp = android.graphics.BitmapFactory.decodeByteArray(
        jpegStream.toByteArray(), 0, jpegStream.size(),
      ) ?: return null

      // Rotate (sensor → upright) and mirror (front camera).
      val matrix = android.graphics.Matrix().apply {
        postRotate(sensorRotation.toFloat())
        postScale(-1f, 1f) // horizontal mirror
      }
      bmp = android.graphics.Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)

      val out = java.io.ByteArrayOutputStream()
      bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, out)
      bmp.recycle()
      out.toByteArray()
    } catch (e: Exception) {
      Log.w(tag, "captureStillJpeg failed: ${e.message}")
      null
    }
  }

  fun dispose() {
    try { if (recording) stopRecording() } catch (_: Exception) {}
    try { cameraProvider?.unbindAll() } catch (_: Exception) {}
    lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    try { detector.close() } catch (_: Exception) {}
    try { analysisExecutor.shutdown() } catch (_: Exception) {}
    textureEntry?.release()
    textureEntry = null
  }

  private fun toPayload(face: Face, width: Int, height: Int, rotation: Int, faceCount: Int, brightness: Double): Map<String, Any> {
    // After rotation the displayed orientation is portrait; face width relative
    // to the displayed frame. Sensor frames are landscape (rotation 90/270), so
    // portrait-display width maps to the sensor bbox height / sensor height.
    val rotated = rotation == 90 || rotation == 270
    val ratio = if (rotated) {
      (face.boundingBox.height().toDouble() / height).coerceIn(0.0, 1.0)
    } else {
      (face.boundingBox.width().toDouble() / width).coerceIn(0.0, 1.0)
    }
    return mapOf(
      "headEulerAngleX" to face.headEulerAngleX.toDouble(),
      "headEulerAngleY" to face.headEulerAngleY.toDouble(),
      "headEulerAngleZ" to face.headEulerAngleZ.toDouble(),
      "smilingProbability" to (face.smilingProbability?.toDouble() ?: 0.0),
      "leftEyeOpenProbability" to (face.leftEyeOpenProbability?.toDouble() ?: 0.0),
      "rightEyeOpenProbability" to (face.rightEyeOpenProbability?.toDouble() ?: 0.0),
      "faceSizeRatio" to ratio,
      // Number of faces in frame — the Dart liveness flow pauses on > 1.
      "faceCount" to faceCount,
      // Mean frame luminance (0–255) for lighting guidance.
      "brightness" to brightness,
    )
  }

  /** Mean luminance (0–255) of the central frame region, from the NV21 Y plane
   *  (the first width*height bytes). Samples a sparse central grid — cheap, and
   *  mirrors the Dart sampler used on iOS. */
  private fun meanLuma(nv21: ByteArray, w: Int, h: Int): Double {
    if (w <= 0 || h <= 0) return 128.0
    val x0 = w / 4; val x1 = w * 3 / 4
    val y0 = h / 4; val y1 = h * 3 / 4
    val sx = ((x1 - x0) / 16).coerceAtLeast(1)
    val sy = ((y1 - y0) / 12).coerceAtLeast(1)
    var total = 0L
    var count = 0
    var y = y0
    while (y < y1) {
      val row = y * w
      var x = x0
      while (x < x1) {
        val idx = row + x
        if (idx < nv21.size) { total += (nv21[idx].toInt() and 0xFF); count++ }
        x += sx
      }
      y += sy
    }
    return if (count > 0) total.toDouble() / count else 128.0
  }
}
