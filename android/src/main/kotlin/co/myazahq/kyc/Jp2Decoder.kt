package co.myazahq.kyc

import android.graphics.Bitmap
import jj2000.j2k.codestream.HeaderInfo
import jj2000.j2k.codestream.reader.BitstreamReaderAgent
import jj2000.j2k.codestream.reader.HeaderDecoder
import jj2000.j2k.decoder.Decoder
import jj2000.j2k.fileformat.reader.FileFormatReader
import jj2000.j2k.image.DataBlkInt
import jj2000.j2k.image.ImgDataConverter
import jj2000.j2k.image.invcomptransf.InvCompTransf
import jj2000.j2k.util.ISRandomAccessIO
import jj2000.j2k.util.ParameterList
import jj2000.j2k.wavelet.synthesis.InverseWT
import java.io.ByteArrayInputStream

/**
 * JPEG 2000 → Bitmap, for the DG2 chip portrait.
 *
 * Android's BitmapFactory has NO JPEG 2000 decoder, and no platform API ever
 * will — on iOS, ImageIO registers `public.jpeg-2000`, which is why the chip
 * portrait always appeared there and never here. Most passports store DG2 as
 * JPEG 2000, so "Android shows the generic tick" was the common case, not the
 * exception.
 *
 * So the decoder is bundled: JJ2000, the JPEG 2000 reference implementation
 * (pure Java, `edu.ucar:jj2000`), driven through the same
 * header → bitstream → entropy → dequant → inverse-DWT → inverse-CT chain
 * JMRTD's Android decoder uses.
 *
 * Ported verbatim from the React Native SDK's Jp2Decoder, which has been
 * rendering this on Android since PACE landed. Keep the two in step: a fix to
 * one is a fix to both.
 *
 * Null on ANY failure, including exotic codestreams — the portrait is a
 * courtesy and the caller falls back to the generic mark.
 */
internal object Jp2Decoder {

  fun decode(bytes: ByteArray): Bitmap? =
    try {
      decodeUnsafe(bytes)
    } catch (_: Throwable) {
      null
    }

  private fun decodeUnsafe(bytes: ByteArray): Bitmap? {
    val input = ISRandomAccessIO(ByteArrayInputStream(bytes), bytes.size, 1, bytes.size)

    // The decoder's own defaults; JJ2000 refuses to run without a full list.
    val defaults = ParameterList()
    for (p in Decoder.getAllParameters()) if (p[3] != null) defaults[p[0]] = p[3]
    val pl = ParameterList(defaults)

    // DG2 stores either a bare codestream or the full JP2 container; the
    // FileFormatReader tells them apart and finds the codestream box.
    val ff = FileFormatReader(input)
    ff.readFileFormat()
    if (ff.JP2FFUsed) input.seek(ff.firstCodeStreamPos)

    val hi = HeaderInfo()
    val hd = HeaderDecoder(input, pl, hi)
    val nComp = hd.numComps
    if (nComp != 1 && nComp != 3) return null
    val depth = IntArray(nComp) { hd.getOriginalBitDepth(it) }
    val decSpec = hd.decoderSpecs

    val reader = BitstreamReaderAgent.createInstance(input, hd, pl, decSpec, false, hi)
    val entropy = hd.createEntropyDecoder(reader, pl)
    val roi = hd.createROIDeScaler(entropy, pl, decSpec)
    val dequant = hd.createDequantizer(roi, depth, decSpec)
    val invWT = InverseWT.createInstance(dequant, decSpec)
    invWT.setImgResLevel(reader.imgRes)
    val converter = ImgDataConverter(invWT, 0)
    val ict = InvCompTransf(converter, decSpec, depth, pl)

    ict.setTile(0, 0)
    val width = ict.imgWidth
    val height = ict.imgHeight
    if (width <= 0 || height <= 0 || width * height > 4_000_000) return null
    // Subsampled components would need per-component upsampling; every real
    // DG2 portrait observed is 4:4:4 or grayscale, so anything else bails to
    // the caller's fallback rather than risking a garbled face.
    for (c in 0 until nComp) {
      if (ict.getCompImgWidth(c) != width || ict.getCompImgHeight(c) != height) return null
    }

    val channels = Array(nComp) { c ->
      val blk = DataBlkInt(0, 0, width, height)
      var out = ict.getInternCompData(blk, c) as DataBlkInt
      // A progressive return means the data isn't final yet — ask again.
      while (out.progressive) out = ict.getInternCompData(out, c) as DataBlkInt

      val fixed = ict.getFixedPoint(c)
      val shift = 1 shl (depth[c] - 1)
      val max = (1 shl depth[c]) - 1
      val plane = IntArray(width * height)
      for (y in 0 until height) {
        var src = out.offset + y * out.scanw
        var dst = y * width
        for (x in 0 until width) {
          // Undo the fixed-point scaling, then the DC level shift, clamp to
          // the component's range, and normalise to 8 bits.
          var v = (out.data[src] shr fixed) + shift
          if (v < 0) v = 0 else if (v > max) v = max
          plane[dst] = if (max == 255) v else (v * 255) / max
          src += 1
          dst += 1
        }
      }
      plane
    }

    val argb = IntArray(width * height)
    val r = channels[0]
    val g = if (nComp == 3) channels[1] else channels[0]
    val b = if (nComp == 3) channels[2] else channels[0]
    for (i in argb.indices) {
      argb[i] = (0xFF shl 24) or (r[i] shl 16) or (g[i] shl 8) or b[i]
    }
    return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
  }
}
