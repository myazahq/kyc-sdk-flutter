package co.myazahq.kyc

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/**
 * Android side of the Myaza KYC SDK. Two responsibilities:
 *
 *  1. **Per-frame face detection** (`kyc_sdk_flutter/face_detection`) — the
 *     original method channel: Dart sends an NV21 frame, we return ML Kit face
 *     signals. Used by code paths that drive their own camera (the Flutter
 *     camera-plugin liveness path, kept as a fallback).
 *
 *  2. **Native liveness recorder** (`kyc_sdk_flutter/liveness_recorder` method
 *     channel + `kyc_sdk_flutter/liveness_recorder/faces` event channel) — owns
 *     the camera via CameraX, runs ONE ImageAnalysis stream fanned to both ML
 *     Kit (face signals streamed over the event channel) and a MediaCodec
 *     encoder (a clip that shows the gestures). Solves the CameraX use-case cap
 *     that broke record-while-detecting with the Flutter camera plugin.
 *
 * Keeping ML Kit Android-only (Gradle) means no GoogleMLKit CocoaPod on iOS, so
 * the SDK still builds for Apple-Silicon iOS simulators (iOS uses Apple Vision).
 */
class KycSdkFlutterPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var recorderChannel: MethodChannel
  private lateinit var faceEventChannel: EventChannel

  private lateinit var appContext: Context
  private lateinit var textures: TextureRegistry
  private val mainHandler = Handler(Looper.getMainLooper())

  private var faceSink: EventChannel.EventSink? = null
  private var recorder: LivenessRecorder? = null

  private val detector: FaceDetector by lazy {
    FaceDetection.getClient(
      FaceDetectorOptions.Builder()
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .enableTracking()
        .setMinFaceSize(0.15f)
        .build(),
    )
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    textures = binding.textureRegistry

    channel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/face_detection")
    channel.setMethodCallHandler(this)

    recorderChannel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/liveness_recorder")
    recorderChannel.setMethodCallHandler(this)

    faceEventChannel = EventChannel(binding.binaryMessenger, "kyc_sdk_flutter/liveness_recorder/faces")
    faceEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        faceSink = events
      }
      override fun onCancel(arguments: Any?) {
        faceSink = null
      }
    })
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    recorderChannel.setMethodCallHandler(null)
    faceEventChannel.setStreamHandler(null)
    recorder?.dispose()
    recorder = null
    detector.close()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "detect" -> handleDetect(call, result)
      "startRecorder" -> handleStartRecorder(result)
      "startRecording" -> {
        recorder?.startRecording()
        result.success(null)
      }
      "stopRecording" -> {
        val path = recorder?.stopRecording()
        result.success(path)
      }
      "captureStill" -> {
        val q = call.argument<Int>("quality") ?: 90
        result.success(recorder?.captureStillJpeg(q))
      }
      "disposeRecorder" -> {
        recorder?.dispose()
        recorder = null
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  // ── Native liveness recorder ────────────────────────────────────────────────

  private fun handleStartRecorder(result: Result) {
    recorder?.dispose()
    recorder = null

    val rec = LivenessRecorder(appContext, textures) { payload ->
      // Stream face signals to Dart on the main thread.
      mainHandler.post { faceSink?.success(payload) }
    }
    recorder = rec
    rec.start(
      onReady = { textureId ->
        mainHandler.post {
          result.success(
            mapOf(
              "textureId" to textureId,
              "rotation" to rec.rotationDegrees,
              "previewWidth" to rec.previewBufferWidth,
              "previewHeight" to rec.previewBufferHeight,
            ),
          )
        }
      },
      onError = { msg -> mainHandler.post { result.error("recorder_start_failed", msg, null) } },
    )
  }

  // ── Per-frame detection (method-channel fallback) ───────────────────────────

  private fun handleDetect(call: MethodCall, result: Result) {
    @Suppress("UNCHECKED_CAST")
    val planes = call.argument<List<Map<String, Any>>>("planes")
    val width = call.argument<Int>("width")
    val height = call.argument<Int>("height")
    val sensorOrientation = call.argument<Int>("sensorOrientation") ?: 0
    val firstPlane = planes?.firstOrNull()
    val bytes = firstPlane?.get("bytes") as? ByteArray

    if (bytes == null || width == null || height == null) {
      result.success(null)
      return
    }

    val image = InputImage.fromByteArray(
      bytes, width, height, sensorOrientation, InputImage.IMAGE_FORMAT_NV21,
    )
    detector.process(image)
      .addOnSuccessListener { faces ->
        val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
        result.success(face?.let { toPayload(it, width, height, faces.size) })
      }
      .addOnFailureListener { result.success(null) }
  }

  private fun toPayload(face: Face, width: Int, height: Int, faceCount: Int): Map<String, Any> {
    val isLandscape = width > height
    val ratio = if (isLandscape) {
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
    )
  }
}
