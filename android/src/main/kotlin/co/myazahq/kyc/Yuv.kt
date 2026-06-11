package co.myazahq.kyc

import android.graphics.ImageFormat
import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer

/**
 * YUV conversion helpers shared by the liveness recorder.
 *
 * CameraX `ImageAnalysis` delivers `YUV_420_888` frames. We need two things from
 * each frame:
 *   • NV21 bytes for ML Kit (`InputImage.fromByteArray(..., IMAGE_FORMAT_NV21)`)
 *   • I420 (YUV420 planar) for the MediaCodec encoder configured with
 *     `COLOR_FormatYUV420Flexible` (encoders accept I420 / planar reliably).
 *
 * `YUV_420_888` has per-plane row/pixel strides that vary by device, so we copy
 * plane-by-plane honoring strides rather than assuming a packed layout.
 */
object Yuv {

  /** Converts a [YUV_420_888] [ImageProxy] to NV21 (Y plane + interleaved VU). */
  fun toNv21(image: ImageProxy): ByteArray {
    val width = image.width
    val height = image.height
    val ySize = width * height
    val out = ByteArray(ySize + 2 * (width / 2) * (height / 2))

    val yPlane = image.planes[0]
    val uPlane = image.planes[1]
    val vPlane = image.planes[2]

    // --- Y ---
    copyPlane(yPlane.buffer, yPlane.rowStride, yPlane.pixelStride, width, height, out, 0)

    // --- VU interleaved (NV21 = Y then V,U,V,U...) ---
    val chromaWidth = width / 2
    val chromaHeight = height / 2
    val vBuf = vPlane.buffer
    val uBuf = uPlane.buffer
    val vRowStride = vPlane.rowStride
    val uRowStride = uPlane.rowStride
    val vPixelStride = vPlane.pixelStride
    val uPixelStride = uPlane.pixelStride

    var offset = ySize
    for (row in 0 until chromaHeight) {
      var vIndex = row * vRowStride
      var uIndex = row * uRowStride
      for (col in 0 until chromaWidth) {
        out[offset++] = vBuf.get(vIndex)
        out[offset++] = uBuf.get(uIndex)
        vIndex += vPixelStride
        uIndex += uPixelStride
      }
    }
    return out
  }

  /**
   * Converts a [YUV_420_888] [ImageProxy] to I420 (planar Y, then full U, then
   * full V) — the layout MediaCodec's `COLOR_FormatYUV420Flexible` accepts in
   * byte-buffer mode. Written into [dest] starting at offset 0.
   */
  fun toI420(image: ImageProxy, dest: ByteArray) {
    val width = image.width
    val height = image.height
    val ySize = width * height
    val chromaWidth = width / 2
    val chromaHeight = height / 2
    val chromaSize = chromaWidth * chromaHeight

    val yPlane = image.planes[0]
    val uPlane = image.planes[1]
    val vPlane = image.planes[2]

    // Y
    copyPlane(yPlane.buffer, yPlane.rowStride, yPlane.pixelStride, width, height, dest, 0)
    // U (Cb)
    copyChromaPlanar(
      uPlane.buffer, uPlane.rowStride, uPlane.pixelStride,
      chromaWidth, chromaHeight, dest, ySize,
    )
    // V (Cr)
    copyChromaPlanar(
      vPlane.buffer, vPlane.rowStride, vPlane.pixelStride,
      chromaWidth, chromaHeight, dest, ySize + chromaSize,
    )
  }

  fun i420Size(width: Int, height: Int): Int =
    width * height + 2 * (width / 2) * (height / 2)

  private fun copyPlane(
    buffer: ByteBuffer,
    rowStride: Int,
    pixelStride: Int,
    width: Int,
    height: Int,
    out: ByteArray,
    outOffset: Int,
  ) {
    var pos = outOffset
    if (pixelStride == 1 && rowStride == width) {
      // Tightly packed — bulk copy.
      val dup = buffer.duplicate()
      dup.position(0)
      dup.get(out, outOffset, width * height)
      return
    }
    for (row in 0 until height) {
      var idx = row * rowStride
      for (col in 0 until width) {
        out[pos++] = buffer.get(idx)
        idx += pixelStride
      }
    }
  }

  private fun copyChromaPlanar(
    buffer: ByteBuffer,
    rowStride: Int,
    pixelStride: Int,
    width: Int,
    height: Int,
    out: ByteArray,
    outOffset: Int,
  ) {
    var pos = outOffset
    for (row in 0 until height) {
      var idx = row * rowStride
      for (col in 0 until width) {
        out[pos++] = buffer.get(idx)
        idx += pixelStride
      }
    }
  }
}
