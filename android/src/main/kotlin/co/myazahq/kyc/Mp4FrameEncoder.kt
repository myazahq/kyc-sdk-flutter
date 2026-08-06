package co.myazahq.kyc

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.nio.ByteBuffer

/**
 * Minimal H.264 encoder that turns a stream of I420 frames into an MP4 file via
 * MediaCodec + MediaMuxer, in byte-buffer (not Surface) mode so it can be fed
 * the same frames ImageAnalysis hands to ML Kit.
 *
 * Aggressive-but-clear settings matching the SDK's "small proof clip" budget:
 * ~720p max, modest bitrate, 15fps. Shared by [LivenessRecorder] (gesture clip)
 * and [DocumentCamera] (per-side clip); all calls are expected on the single
 * worker thread owned by whichever one created it.
 */
class Mp4FrameEncoder(
  private val width: Int,
  private val height: Int,
  private val outputPath: String,
  private val rotationDegrees: Int,
) {
  private val tag = "KycMp4Encoder"
  private var codec: MediaCodec? = null
  private var muxer: MediaMuxer? = null
  private var trackIndex = -1
  private var muxerStarted = false
  private var frameIndex = 0L
  private val frameDurationUs = 1_000_000L / FPS
  private val bufferInfo = MediaCodec.BufferInfo()
  private var started = false

  fun start() {
    val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
      setInteger(
        MediaFormat.KEY_COLOR_FORMAT,
        MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
      )
      setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
      setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
      setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
    }
    codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
      configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
      start()
    }
    muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).apply {
      setOrientationHint(rotationDegrees)
    }
    started = true
  }

  /** Feeds one I420 frame. No-op if not started. */
  fun encodeI420(i420: ByteArray) {
    val c = codec ?: return
    if (!started) return
    try {
      val inIndex = c.dequeueInputBuffer(10_000)
      if (inIndex >= 0) {
        // Write through the codec's input Image so we honor ITS plane row/pixel
        // strides. Copying packed I420 straight into the raw ByteBuffer assumes a
        // layout the encoder may not use (COLOR_FormatYUV420Flexible varies by
        // device) — that mismatch is what produced the green/magenta striping.
        val image = c.getInputImage(inIndex)
        if (image != null) {
          writeI420ToImage(i420, image)
        } else {
          // Fallback: raw buffer (older devices).
          val inBuf: ByteBuffer = c.getInputBuffer(inIndex) ?: return
          inBuf.clear()
          inBuf.put(i420)
        }
        val ptsUs = frameIndex * frameDurationUs
        val size = width * height * 3 / 2
        c.queueInputBuffer(inIndex, 0, size, ptsUs, 0)
        frameIndex++
      }
      drain(false)
    } catch (e: Exception) {
      Log.w(tag, "encode frame failed", e)
    }
  }

  /** Copies packed I420 (Y plane, U plane, V plane) into a codec input [Image],
   *  honoring each plane's rowStride/pixelStride. */
  private fun writeI420ToImage(i420: ByteArray, image: android.media.Image) {
    val chromaW = width / 2
    val chromaH = height / 2
    val ySize = width * height
    val uSize = chromaW * chromaH

    val planes = image.planes
    // Y
    copyToPlane(i420, 0, width, height, planes[0])
    // U (Cb) — second plane in I420
    copyToPlane(i420, ySize, chromaW, chromaH, planes[1])
    // V (Cr) — third plane in I420
    copyToPlane(i420, ySize + uSize, chromaW, chromaH, planes[2])
  }

  private fun copyToPlane(
    src: ByteArray,
    srcOffset: Int,
    w: Int,
    h: Int,
    plane: android.media.Image.Plane,
  ) {
    val buf = plane.buffer
    val rowStride = plane.rowStride
    val pixelStride = plane.pixelStride
    val limit = buf.limit()
    var srcPos = srcOffset
    if (pixelStride == 1) {
      // Packed plane: copy w contiguous bytes per row, clamped to the buffer's
      // remaining space. The last row of a codec plane is often shorter than a
      // full rowStride, so an unclamped `put` overflows it (BufferOverflowException
      // — null message — which is what silently killed every frame).
      for (row in 0 until h) {
        val dst = row * rowStride
        if (dst >= limit) break
        val n = minOf(w, limit - dst)
        buf.position(dst)
        buf.put(src, srcPos, n)
        srcPos += w
      }
    } else {
      // Strided chroma (semi-planar NV12/NV21): place each sample pixelStride
      // apart with absolute puts so we never read past the row or write past the
      // buffer limit.
      for (row in 0 until h) {
        var dst = row * rowStride
        var col = 0
        while (col < w && dst < limit) {
          buf.put(dst, src[srcPos + col])
          dst += pixelStride
          col++
        }
        srcPos += w
      }
    }
  }

  /** Flushes, finalizes the MP4, releases resources. Safe to call once. */
  fun stop() {
    if (!started) return
    started = false
    try {
      val c = codec
      if (c != null) {
        val inIndex = c.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
          c.queueInputBuffer(
            inIndex, 0, 0, frameIndex * frameDurationUs,
            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
          )
        }
        drain(true)
      }
    } catch (e: Exception) {
      Log.w(tag, "stop/drain failed: ${e.message}")
    } finally {
      release()
    }
  }

  private fun drain(endOfStream: Boolean) {
    val c = codec ?: return
    while (true) {
      val outIndex = c.dequeueOutputBuffer(bufferInfo, 10_000)
      when {
        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
          if (muxerStarted) throw IllegalStateException("format changed twice")
          trackIndex = muxer!!.addTrack(c.outputFormat)
          muxer!!.start()
          muxerStarted = true
        }
        outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
          if (!endOfStream) return // no more output for now
          // else keep looping until EOS flag arrives
        }
        outIndex >= 0 -> {
          val encoded = c.getOutputBuffer(outIndex)
          if (encoded != null && bufferInfo.size > 0 && muxerStarted &&
            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
          ) {
            encoded.position(bufferInfo.offset)
            encoded.limit(bufferInfo.offset + bufferInfo.size)
            muxer!!.writeSampleData(trackIndex, encoded, bufferInfo)
          }
          c.releaseOutputBuffer(outIndex, false)
          if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
        }
      }
    }
  }

  private fun release() {
    try { codec?.stop() } catch (_: Exception) {}
    try { codec?.release() } catch (_: Exception) {}
    try { if (muxerStarted) muxer?.stop() } catch (e: Exception) { Log.w(tag, "muxer.stop failed", e) }
    try { muxer?.release() } catch (_: Exception) {}
    codec = null
    muxer = null
  }

  companion object {
    private const val FPS = 15
    private const val BITRATE = 2_500_000 // ~2.5 Mbps @ ~720p — small but clear
  }
}
