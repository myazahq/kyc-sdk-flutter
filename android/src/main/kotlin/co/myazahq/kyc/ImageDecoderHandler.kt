package co.myazahq.kyc

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Android side of `kyc_sdk_flutter/image_decode`.
 *
 * Until this existed the channel was implemented on iOS ONLY, so every Android
 * call landed on `MissingPluginException`, which `decodeDg2Portrait` maps to
 * null. The chip portrait therefore never appeared on Android and the success
 * screen fell back to the generic tick — even though the read had the photo in
 * hand. The React Native SDK has shown it on Android all along.
 *
 * Contract matches ImageDecoder.swift exactly: takes `bytes`, returns JPEG
 * bytes, and returns null rather than failing. The portrait is a courtesy
 * preview and the chip read stands on its own without it.
 */
internal class ImageDecoderHandler {

  // A full-resolution portrait is a few hundred kilobytes of wavelet data, and
  // JJ2000 is pure Java — decoding it on the platform thread would stall
  // frames. Single-threaded: one portrait per read, and serialising costs
  // nothing while bounding the work.
  private val worker = Executors.newSingleThreadExecutor()

  fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
    if (call.method != "decode") return false

    val bytes = call.argument<ByteArray>("bytes")
    if (bytes == null || bytes.isEmpty()) {
      result.success(null)
      return true
    }

    worker.execute {
      val jpeg = transcodeToJpeg(bytes)
      // Flutter requires results on the platform thread.
      mainThread { result.success(jpeg) }
    }
    return true
  }

  fun dispose() {
    worker.shutdownNow()
  }

  private fun mainThread(block: () -> Unit) {
    android.os.Handler(android.os.Looper.getMainLooper()).post(block)
  }

  /**
   * Baseline JPEG first (BitmapFactory handles it and is far faster), then the
   * bundled JPEG 2000 decoder, which is what most passports actually need.
   */
  private fun transcodeToJpeg(bytes: ByteArray): ByteArray? =
    try {
      val bitmap: Bitmap? =
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: Jp2Decoder.decode(bytes)
      bitmap?.let {
        val out = ByteArrayOutputStream()
        it.compress(Bitmap.CompressFormat.JPEG, 90, out)
        it.recycle()
        out.toByteArray()
      }
    } catch (_: Throwable) {
      null
    }
}
