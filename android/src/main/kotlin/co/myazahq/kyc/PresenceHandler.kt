package co.myazahq.kyc

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.concurrent.thread

/**
 * Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
 * Dart owns the permission escalation, but the step up to "Allow all the
 * time" is asked natively ([PresenceAlwaysPermission]): geolocator's own
 * request is ignored by Android 11 and later. This side persists the reporter
 * config and arms/disarms the fence.
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
          if (ok) {
            store.saveConfig(config)
            PresenceCheckInWorker.schedule(context)
          } else {
            store.armed = false
          }
          result.success(ok)
        }
      }
      // An app-open reading the Dart reporter already took. Inside, it records
      // the running stay now instead of when the person leaves. A no-op unless
      // the background tier is armed. Off the main thread: it may flush.
      "presenceCheckIn" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val timestamp = call.argument<Number>("timestamp")?.toLong()
        val store = PresenceStore(context)
        val config = store.loadConfig()
        if (lat == null || lng == null || timestamp == null || !store.armed || config == null) {
          result.success(false)
          return true
        }
        val fix = PresenceSampler.Fix(
          lat = lat,
          lng = lng,
          accuracy = call.argument<Number>("accuracy")?.toDouble(),
          timestamp = timestamp,
          mocked = call.argument<Boolean>("mocked"),
        )
        thread(name = "myaza-presence-checkin") { PresenceCheckInWorker.applyCheckIn(store, config, fix) }
        result.success(true)
      }
      "disablePresence" -> {
        PresenceCheckInWorker.cancel(context)
        PresenceGeofencer.disarm(context)
        PresenceStore(context).clear()
        result.success(null)
      }
      "isPresenceArmed" -> result.success(PresenceStore(context).armed)
      // The open stay, for the host to show: when the person arrived and when
      // the next check-in can record it. Null with no stay open.
      "presenceStay" -> {
        val store = PresenceStore(context)
        val enterAt = store.enterAt
        result.success(
          if (!store.armed || enterAt == null) null
          else mapOf(
            "since" to (store.stayStart ?: enterAt),
            "nextReportAt" to PresenceFold.nextCheckpointAt(enterAt, store.stayStart),
          ),
        )
      }
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
