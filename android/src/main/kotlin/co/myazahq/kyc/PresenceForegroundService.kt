package co.myazahq.kyc

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.util.TimeZone
import kotlin.concurrent.thread

/**
 * The Android foreground-service tier (the OkHi reliability move). A
 * persistent notification keeps this process alive on phones whose battery
 * managers drop geofence transitions; low-power fixes every few minutes run
 * through PresenceSampler onto the SAME stored enterAt the geofence receiver
 * uses, the queue flushes while the process is alive, and the fence is
 * re-armed whenever the location toggle comes back on. START_STICKY, so a
 * kill is a restart; the boot receiver restarts it after a reboot.
 *
 * The HOST declares this service (with foregroundServiceType="location") and
 * the FOREGROUND_SERVICE / FOREGROUND_SERVICE_LOCATION permissions in its own
 * manifest — the same stance as background location, and for the same
 * reason. PresenceHandler refuses to start an undeclared one.
 */
class PresenceForegroundService : Service() {
  companion object {
    const val NOTIFICATION_ID = 4472
    private const val SAMPLE_INTERVAL_MS = 10L * 60 * 1000
    private const val SAMPLE_DISTANCE_M = 100f

    /** Process-local "is it up right now"; the store's serviceEnabled is the
     *  durable intent the boot receiver reads. */
    @Volatile var running: Boolean = false
      private set

    fun start(context: Context): Boolean = try {
      val intent = Intent(context, PresenceForegroundService::class.java)
      val started = if (Build.VERSION.SDK_INT >= 26) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
      started != null
    } catch (_: Exception) {
      false
    }

    fun stop(context: Context) {
      try {
        context.stopService(Intent(context, PresenceForegroundService::class.java))
      } catch (_: Exception) {
        // Not running — already stopped.
      }
    }
  }

  private var fused: FusedLocationProviderClient? = null
  private var providersReceiver: BroadcastReceiver? = null

  private val callback = object : LocationCallback() {
    override fun onLocationResult(result: LocationResult) = handle(result)
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val store = PresenceStore(this)
    val config = store.loadConfig()
    if (!store.serviceEnabled || config == null) {
      stopSelf()
      return START_NOT_STICKY
    }
    try {
      val notification = buildNotification(store)
      if (Build.VERSION.SDK_INT >= 29) {
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
    } catch (_: Exception) {
      // API 34 refuses a location-typed service the manifest never declared
      // the permission for. Record the downgrade so presenceStatus() can say.
      store.serviceEnabled = false
      stopSelf()
      return START_NOT_STICKY
    }
    running = true
    requestUpdates()
    watchProviders()
    // Idempotent: registering the same request id replaces the fence, and a
    // fence dropped by a location toggle comes back this way.
    PresenceGeofencer.arm(this, config) { ok -> if (ok) store.armed = true }
    return START_STICKY
  }

  @SuppressLint("MissingPermission")
  private fun requestUpdates() {
    if (fused != null) return
    try {
      val client = LocationServices.getFusedLocationProviderClient(this)
      val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, SAMPLE_INTERVAL_MS)
        .setMinUpdateDistanceMeters(SAMPLE_DISTANCE_M)
        .setMinUpdateIntervalMillis(SAMPLE_INTERVAL_MS / 2)
        .build()
      client.requestLocationUpdates(request, callback, Looper.getMainLooper())
      fused = client
    } catch (_: Exception) {
      // Permission revoked since enable; the fence receiver still runs.
    }
  }

  private fun watchProviders() {
    if (providersReceiver != null) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != LocationManager.PROVIDERS_CHANGED_ACTION) return
        val store = PresenceStore(context)
        val config = store.loadConfig() ?: return
        PresenceGeofencer.arm(context, config) { ok -> if (ok) store.armed = true }
      }
    }
    ContextCompat.registerReceiver(
      this, receiver, IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION),
      ContextCompat.RECEIVER_NOT_EXPORTED,
    )
    providersReceiver = receiver
  }

  private fun handle(result: LocationResult) {
    val store = PresenceStore(this)
    val config = store.loadConfig() ?: return
    val fixes = result.locations.map { l ->
      PresenceSampler.Fix(
        lat = l.latitude,
        lng = l.longitude,
        accuracy = if (l.hasAccuracy()) l.accuracy.toDouble() else null,
        timestamp = l.time,
        mocked = if (Build.VERSION.SDK_INT >= 31) l.isMock else @Suppress("DEPRECATION") l.isFromMockProvider,
      )
    }
    if (fixes.isEmpty()) return
    val now = fixes.maxOf { it.timestamp }
    val offsetMinutes = TimeZone.getDefault().getOffset(now) / 60_000
    val out = PresenceSampler.apply(config.lat, config.lng, fixes, store.enterAt, offsetMinutes)
    store.enterAt = out.enterAt
    if (out.days.isNotEmpty()) store.queueDays(out.days)
    for (f in out.flagged) store.queueFlagged(f.day, f.nightPresent)
    // A live process is the one moment a stuck queue (an EXIT flush that met
    // no network) can drain.
    thread(name = "myaza-presence-service-flush") { PresenceGeofencer.flushQueue(store) }
  }

  private fun buildNotification(store: PresenceStore): Notification {
    val n = store.loadNotification()
    val channelId = n.channelId
    if (Build.VERSION.SDK_INT >= 26) {
      val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      val channel = NotificationChannel(channelId, n.channelName, NotificationManager.IMPORTANCE_LOW)
      n.channelDescription?.let { channel.description = it }
      manager.createNotificationChannel(channel)
    }
    val launch = packageManager.getLaunchIntentForPackage(packageName)
    val immutable = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
    val tap = launch?.let {
      PendingIntent.getActivity(this, 4473, it, PendingIntent.FLAG_UPDATE_CURRENT or immutable)
    }
    val builder = NotificationCompat.Builder(this, channelId)
      .setContentTitle(n.title)
      .setContentText(n.body)
      .setSmallIcon(applicationInfo.icon)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
    n.color?.let { builder.setColor(it) }
    tap?.let { builder.setContentIntent(it) }
    return builder.build()
  }

  override fun onDestroy() {
    running = false
    try {
      fused?.removeLocationUpdates(callback)
    } catch (_: Exception) {
      // Already gone.
    }
    fused = null
    providersReceiver?.let {
      try {
        unregisterReceiver(it)
      } catch (_: Exception) {
        // Not registered.
      }
    }
    providersReceiver = null
    super.onDestroy()
  }
}
