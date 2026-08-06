package co.myazahq.kyc

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * On-device text recognition for MRZ scanning (ML Kit, Latin script).
 *
 * Mirrors the iOS TextRecognizer: Dart sends one NV21 camera frame, we return
 * the recognized lines and the Dart side does all MRZ parsing/validation. ML
 * Kit has no "disable language correction" switch like Vision, so the MRZ
 * filler runs occasionally come back mangled — which is fine, because nothing
 * is accepted until the 7-3-1 check digits validate, so a bad frame is simply
 * skipped and the next one tried.
 */
class TextRecognizerHandler {
  private val recognizer =
    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

  fun recognize(call: MethodCall, result: MethodChannel.Result) {
    val width = call.argument<Int>("width")
    val height = call.argument<Int>("height")
    val sensorOrientation = call.argument<Int>("sensorOrientation") ?: 0
    val planes = call.argument<List<Map<String, Any>>>("planes")
    val bytes = planes?.firstOrNull()?.get("bytes") as? ByteArray

    if (width == null || height == null || bytes == null) {
      result.success(null)
      return
    }

    val image = InputImage.fromByteArray(
      bytes, width, height, sensorOrientation, InputImage.IMAGE_FORMAT_NV21,
    )

    recognizer.process(image)
      .addOnSuccessListener { text ->
        val lines = ArrayList<String>()
        for (block in text.textBlocks) {
          for (line in block.lines) lines.add(line.text)
        }
        result.success(mapOf("lines" to lines))
      }
      .addOnFailureListener { result.success(null) }
  }

  /**
   * Recognizes an encoded still (JPEG/PNG) — used to pull the MRZ out of the
   * document photo the user already captured, so the chip step needs no second
   * camera pass.
   */
  fun recognizeBytes(call: MethodCall, result: MethodChannel.Result) {
    val bytes = call.argument<ByteArray>("bytes")
    if (bytes == null) {
      result.success(null)
      return
    }
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    if (bitmap == null) {
      result.success(null)
      return
    }

    recognizer.process(InputImage.fromBitmap(bitmap, 0))
      .addOnSuccessListener { text ->
        val lines = ArrayList<String>()
        for (block in text.textBlocks) {
          for (line in block.lines) lines.add(line.text)
        }
        result.success(mapOf("lines" to lines))
      }
      .addOnFailureListener { result.success(null) }
  }

  fun close() {
    recognizer.close()
  }
}
