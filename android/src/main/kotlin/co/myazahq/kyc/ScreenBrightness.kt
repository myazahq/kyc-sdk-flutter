package co.myazahq.kyc

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android side of `kyc_sdk_flutter/capture_tuning`: the screen's brightness for
 * the liveness step. iOS also locks white balance and exposure on this channel;
 * here the camera plugin's own session owns those, so only the screen is ours.
 *
 * The brightness is the ACTIVITY WINDOW's own (`screenBrightness` on its
 * layout params), never the system setting: no WRITE_SETTINGS, and Android
 * drops the override on its own the moment the window leaves the screen. The
 * saved value is usually BRIGHTNESS_OVERRIDE_NONE (follow the system), which is
 * exactly what restoring it puts back.
 *
 * Two holders share the screen: the flash sequence (`beginFlash` / `restore`)
 * and the bright-screen liveness (`setBrightness` / `restoreBrightness`), which
 * keeps the screen at full while the selfie camera is on. Each releases only
 * itself; the saved value comes back when the LAST one lets go. Every call is
 * best-effort: no activity attached, or a window that refuses, is a no-op
 * reported as success, because a brighter screen is an aid, never a gate.
 */
class ScreenBrightness {
  private var activity: Activity? = null
  private val holders = mutableSetOf<String>()

  /** The window's value before the first holder raised it; null when none holds. */
  private var previous: Float? = null

  /** The level the holders asked for, re-applied to a recreated window. */
  private var level = 1f

  fun attach(activity: Activity) {
    this.activity = activity
    // A recreated window starts at the system level: re-apply a live hold.
    if (holders.isNotEmpty()) apply(level)
  }

  fun detach() {
    activity = null
  }

  /** Claims the capture-tuning methods; anything else falls through. */
  fun handle(call: MethodCall, result: Result): Boolean {
    when (call.method) {
      "beginFlash" -> raise(FLASH, call.argument<Double>("brightness"))
      "restore" -> release(FLASH)
      "setBrightness" -> raise(SCREEN, call.argument<Double>("brightness"))
      "restoreBrightness" -> release(SCREEN)
      else -> return false
    }
    result.success(null)
    return true
  }

  private fun raise(holder: String, level: Double?) {
    val window = activity?.window ?: return
    if (previous == null) previous = window.attributes.screenBrightness
    holders.add(holder)
    this.level = (level ?: 1.0).coerceIn(0.0, 1.0).toFloat()
    apply(this.level)
  }

  private fun release(holder: String) {
    holders.remove(holder)
    if (holders.isNotEmpty()) return
    val saved = previous ?: return
    previous = null
    apply(saved)
  }

  private fun apply(value: Float) {
    val window = activity?.window ?: return
    try {
      val params = window.attributes
      params.screenBrightness = value
      window.attributes = params
    } catch (_: Exception) {
      // A window that refuses leaves the screen as it was.
    }
  }

  private companion object {
    const val FLASH = "flash"
    const val SCREEN = "screen"
  }
}
