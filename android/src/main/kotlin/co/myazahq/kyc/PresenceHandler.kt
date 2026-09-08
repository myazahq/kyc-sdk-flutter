package co.myazahq.kyc

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
 * Dart owns the permission escalation (geolocator's two-step to "always");
 * this side only persists the reporter config and arms/disarms the fence.
 */
class PresenceHandler(private val context: Context) {
  /** Returns true when the call was one of ours. */
  fun handle(call: MethodCall, result: Result): Boolean {
    when (call.method) {
      "enablePresence" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val baseUrl = call.argument<String>("baseUrl")
        val apiKey = call.argument<String>("apiKey")
        val externalUserId = call.argument<String>("externalUserId")
        if (lat == null || lng == null || baseUrl == null || apiKey == null || externalUserId == null) {
          result.success(false)
          return true
        }
        val store = PresenceStore(context)
        val config = PresenceStore.Config(
          lat = lat,
          lng = lng,
          radius = (call.argument<Number>("radius") ?: 250).toDouble(),
          baseUrl = baseUrl,
          apiKey = apiKey,
          externalUserId = externalUserId,
        )
        PresenceGeofencer.arm(context, config) { ok ->
          if (ok) store.saveConfig(config) else store.armed = false
          result.success(ok)
        }
      }
      "disablePresence" -> {
        PresenceGeofencer.disarm(context)
        PresenceStore(context).clear()
        result.success(null)
      }
      "isPresenceArmed" -> result.success(PresenceStore(context).armed)
      "enablePresenceService" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val baseUrl = call.argument<String>("baseUrl")
        val apiKey = call.argument<String>("apiKey")
        val externalUserId = call.argument<String>("externalUserId")
        val notification = call.argument<Map<String, Any?>>("notification")
        if (lat == null || lng == null || baseUrl == null || apiKey == null ||
          externalUserId == null || notification == null
        ) {
          result.success("failed")
          return true
        }
        if (!serviceDeclared()) {
          result.success("not_declared")
          return true
        }
        val store = PresenceStore(context)
        store.saveConfig(
          PresenceStore.Config(
            lat = lat,
            lng = lng,
            radius = (call.argument<Number>("radius") ?: 250).toDouble(),
            baseUrl = baseUrl,
            apiKey = apiKey,
            externalUserId = externalUserId,
          ),
        )
        store.saveNotification(
          PresenceStore.NotificationConfig(
            title = notification["title"] as? String ?: "Address verification in progress",
            body = notification["body"] as? String ?: "Open the app to see your progress.",
            channelId = notification["channelId"] as? String ?: "myaza_kyc_presence",
            channelName = notification["channelName"] as? String ?: "Address verification",
            channelDescription = notification["channelDescription"] as? String,
            color = (notification["color"] as? Number)?.toInt(),
          ),
        )
        store.serviceEnabled = true
        val started = PresenceForegroundService.start(context)
        if (!started) store.serviceEnabled = false
        result.success(if (started) "started" else "failed")
      }
      "disablePresenceService" -> {
        PresenceStore(context).serviceEnabled = false
        PresenceForegroundService.stop(context)
        result.success(null)
      }
      "isPresenceServiceRunning" ->
        result.success(PresenceForegroundService.running && PresenceStore(context).serviceEnabled)
      else -> return false
    }
    return true
  }

  /**
   * The host declares the service and its permissions itself (a location
   * foreground service changes the app's review posture). Both are normal,
   * install-time permissions, so checkSelfPermission answers "declared or
   * not" — and an undeclared service resolves to nothing.
   */
  private fun serviceDeclared(): Boolean {
    val resolved = context.packageManager.resolveService(
      Intent(context, PresenceForegroundService::class.java), 0,
    ) != null
    if (!resolved) return false
    val granted = { permission: String ->
      ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
    if (Build.VERSION.SDK_INT >= 28 && !granted(Manifest.permission.FOREGROUND_SERVICE)) return false
    if (Build.VERSION.SDK_INT >= 34 && !granted("android.permission.FOREGROUND_SERVICE_LOCATION")) return false
    return true
  }
}
