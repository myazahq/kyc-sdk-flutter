package co.myazahq.kyc

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream

/**
 * Turns a CameraX [ImageCapture] result into an **upright JPEG with no EXIF
 * orientation to interpret**.
 *
 * CameraX's in-memory capture hands back the sensor's own buffer plus the
 * rotation needed to display it, and how faithfully that rotation reaches EXIF
 * varies by device and CameraX version. The Dart crop runs `bakeOrientation`
 * and then maps the on-screen guide rect into the image, so an orientation the
 * two sides disagree about doesn't just look wrong — it crops the wrong part of
 * the document. Baking the rotation into the pixels here removes the ambiguity
 * entirely.
 */
object DocumentStill {
  private const val TAG = "KycDocumentStill"

  /** Returns upright JPEG bytes, or null if the rotation couldn't be applied
   *  (the caller treats that as a failed capture — better a retake than a
   *  sideways image the crop would take the wrong region from). */
  fun uprightJpeg(image: ImageProxy, quality: Int): ByteArray? {
    val buffer = image.planes[0].buffer
    val jpeg = ByteArray(buffer.remaining())
    buffer.get(jpeg)

    val degrees = ((image.imageInfo.rotationDegrees % 360) + 360) % 360
    if (degrees == 0) return jpeg // already upright — pass the bytes straight through

    var src: Bitmap? = null
    var rotated: Bitmap? = null
    return try {
      src = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
      val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
      rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
      val out = ByteArrayOutputStream(jpeg.size)
      rotated.compress(Bitmap.CompressFormat.JPEG, quality, out)
      out.toByteArray()
    } catch (e: Throwable) {
      // OutOfMemoryError included — a failed rotate must not take the app down.
      Log.w(TAG, "rotate failed (${degrees}°): ${e.message}")
      null
    } finally {
      if (rotated !== src) rotated?.recycle()
      src?.recycle()
    }
  }
}
