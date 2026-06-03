package co.myazahq.kyc

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android face detection for the Myaza KYC Flutter SDK, via Google ML Kit's
 * native Gradle library (com.google.mlkit:face-detection) — NOT the
 * cross-platform Flutter package. Built into the core SDK package. Keeping ML
 * Kit Android-only means no GoogleMLKit CocoaPod on iOS, so the SDK still builds
 * for Apple-Silicon iOS simulators (iOS uses Apple Vision instead).
 *
 * Each call receives one NV21 camera frame and returns the gesture signals the
 * Dart liveness flow expects. ML Kit exposes head pose + smile + eye-open
 * directly, so no landmark math is needed here.
 */
class KycSdkFlutterPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel

  private val detector: FaceDetector by lazy {
    FaceDetection.getClient(
      FaceDetectorOptions.Builder()
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .enableTracking()
        .setMinFaceSize(0.15f)
        .build()
    )
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/face_detection")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    detector.close()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method != "detect") {
      result.notImplemented()
      return
    }

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
      bytes,
      width,
      height,
      sensorOrientation,
      InputImage.IMAGE_FORMAT_NV21
    )

    detector.process(image)
      .addOnSuccessListener { faces ->
        val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
        if (face == null) {
          result.success(null)
          return@addOnSuccessListener
        }
        result.success(toPayload(face, width, height))
      }
      .addOnFailureListener { result.success(null) }
  }

  private fun toPayload(face: Face, width: Int, height: Int): Map<String, Any> {
    // Mirrors the web SDK faceWidth metric. Android delivers frames landscape
    // (sensorOrientation 90°), so portrait-display face width = bbox height /
    // image height; portrait when width <= height.
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
      "faceSizeRatio" to ratio
    )
  }
}
