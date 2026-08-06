package co.myazahq.kyc

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Per-frame ML Kit face detection over the method channel: Dart sends one NV21
 * camera frame, we return the face signals.
 *
 * This is the *fallback* path, used when the Dart side drives its own camera
 * (the Flutter camera-plugin liveness path). The primary Android path is
 * [LivenessRecorder], which detects natively on frames it already owns.
 */
class FaceDetectorHandler {
  private val lazyDetector = lazy {
    FaceDetection.getClient(
      FaceDetectorOptions.Builder()
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .enableTracking()
        .setMinFaceSize(0.15f)
        .build(),
    )
  }
  private val detector: FaceDetector get() = lazyDetector.value

  fun detect(call: MethodCall, result: MethodChannel.Result) {
    @Suppress("UNCHECKED_CAST")
    val planes = call.argument<List<Map<String, Any>>>("planes")
    val width = call.argument<Int>("width")
    val height = call.argument<Int>("height")
    val sensorOrientation = call.argument<Int>("sensorOrientation") ?: 0
    val bytes = planes?.firstOrNull()?.get("bytes") as? ByteArray

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

  /** Closes the detector — without instantiating it if it was never used. */
  fun close() {
    if (lazyDetector.isInitialized()) detector.close()
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
      // Centre of the face in normalised frame coordinates. The liveness flow
      // uses it to tell "the same face moved" from "a different face appeared":
      // size alone cannot, since two people at the same distance measure alike.
      "faceCenterX" to (face.boundingBox.exactCenterX().toDouble() / width).coerceIn(0.0, 1.0),
      "faceCenterY" to (face.boundingBox.exactCenterY().toDouble() / height).coerceIn(0.0, 1.0),
      // Number of faces in frame — the Dart liveness flow pauses on > 1.
      "faceCount" to faceCount,
      // ML Kit's per-face tracking id, stable while it follows the SAME face.
      // A change means a different face, which iOS's Vision cannot report — so
      // it STRENGTHENS the geometric guard rather than replacing it.
      "trackingId" to (face.trackingId ?: -1),
    )
  }
}
