package co.myazahq.kyc

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Records the per-side document clip off the frames [DocumentCamera]'s
 * ImageAnalysis already delivers — no CameraX VideoCapture use case, which is
 * what let the document camera keep Preview + Analysis + ImageCapture (a
 * combination supported on every device) and made stills instant.
 *
 * Starting/stopping a recording touches no camera state at all, so a side change
 * or retake is just stop-then-start rather than a full session restart.
 *
 * [offer] runs on the camera's analysis thread; encoding happens on this class's
 * own handler thread.
 */
class DocumentVideoRecorder(private val context: Context) {

  private val tag = "KycDocumentVideo"

  private var encoderThread: HandlerThread? = null
  private var encoderHandler: Handler? = null
  @Volatile private var encoder: Mp4FrameEncoder? = null
  @Volatile private var recording = false
  private var videoPath: String? = null
  private var lastFrameAtMs = 0L

  /// Frames actually handed to the encoder for THIS clip — the number that
  /// separates "the encoder never ran" from "it ran and produced nothing".
  private var framesOffered = 0

  val isRecording: Boolean get() = recording

  /** Begins a new clip. The encoder itself is created lazily on the first
   *  [offer] so its dimensions match the real sensor frame size. */
  fun start() {
    if (recording) return
    // A counter, not just the clock: a retake can stop one clip and start the
    // next inside the same millisecond, and two clips sharing a path means the
    // second one's muxer truncates the file the first is being uploaded from.
    val name = "kyc_document_${System.currentTimeMillis()}_${nextClipId++}.mp4"
    videoPath = File(context.cacheDir, name).absolutePath
    val thread = HandlerThread("kyc-document-encoder").also { it.start() }
    encoderThread = thread
    encoderHandler = Handler(thread.looper)
    lastFrameAtMs = 0L
    framesOffered = 0
    recording = true
    // Verbose by design: one line per clip, useful when a side video goes
    // missing, noise otherwise.
    Log.d(tag, "clip start $videoPath")
  }

  /**
   * Offers one analysis frame. Frames are taken at [Mp4FrameEncoder]'s own frame
   * rate — the encoder stamps presentation times at a fixed FPS, so feeding it
   * every frame at 30 fps would stretch the clip into slow motion and burn
   * analysis-thread CPU on frames the MP4 doesn't need.
   */
  fun offer(proxy: ImageProxy, rotationDegrees: Int) {
    if (!recording) return
    val now = System.currentTimeMillis()
    if (now - lastFrameAtMs < FRAME_INTERVAL_MS) return
    lastFrameAtMs = now

    val path = videoPath ?: return
    val w = proxy.width
    val h = proxy.height
    val i420 = try {
      ByteArray(Yuv.i420Size(w, h)).also { Yuv.toI420(proxy, it) }
    } catch (e: Exception) {
      Log.w(tag, "i420 convert failed: ${e.message}")
      return
    }

    framesOffered++
    encoderHandler?.post {
      var enc = encoder
      if (enc == null) {
        // A frame already in flight when stop() ran must NEVER create a new
        // encoder. MediaMuxer TRUNCATES its output file the moment it is
        // constructed, so doing so here re-opens the clip that stop() has just
        // finalised and zeroes it — after stop() measured it as good, which is
        // why the logs showed a healthy 1.9 MB clip and the upload found 0
        // bytes. offer() checks `recording` before posting, but the check and
        // the post are not atomic; this is the same check on the far side of
        // the queue, where it is authoritative.
        if (!recording) return@post
        try {
          enc = Mp4FrameEncoder(w, h, path, rotationDegrees)
          enc.start()
          encoder = enc
        } catch (e: Exception) {
          Log.e(tag, "encoder start failed", e)
          return@post
        }
      }
      enc.encodeI420(i420)
    }
  }

  /** Finalises the clip and returns its path (null if nothing was recorded).
   *  Blocks briefly while the encoder drains. */
  fun stop(): String? {
    if (!recording) return null
    recording = false
    val handler = encoderHandler
    val thread = encoderThread
    val latch = CountDownLatch(1)
    handler?.post {
      try { encoder?.stop() } catch (_: Exception) {}
      encoder = null
      latch.countDown()
    } ?: latch.countDown()
    try { latch.await(3, TimeUnit.SECONDS) } catch (_: Exception) {}
    thread?.quitSafely()
    encoderThread = null
    encoderHandler = null
    val path = videoPath ?: return null
    videoPath = null

    // A clip that never received a frame — a stop landing right after a start,
    // which a fast retake can produce — leaves a 0-byte file, because the
    // encoder is created lazily on the first frame and the muxer never wrote a
    // header. Report that as "no clip" rather than handing back an empty file
    // for the caller to compress and upload.
    val file = File(path)
    Log.d(
      tag,
      "clip stop $path exists=${file.exists()} len=${file.length()} " +
        "framesOffered=$framesOffered",
    )
    if (!file.exists() || file.length() == 0L) {
      file.delete()
      Log.i(tag, "discarded empty clip (frames offered: $framesOffered)")
      return null
    }
    return path
  }

  private companion object {
    /** Must match [Mp4FrameEncoder]'s FPS. */
    const val FRAME_INTERVAL_MS = 1000L / 15

    /** Makes every clip path unique even within one millisecond. */
    var nextClipId = 0
  }
}
