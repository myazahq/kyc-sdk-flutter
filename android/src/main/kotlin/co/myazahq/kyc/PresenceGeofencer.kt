package co.myazahq.kyc

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Arms/disarms the OS geofence and owns the flush wire. Shared by the channel
 * handler (enable/disable), the boot receiver (re-arm after restart) and the
 * geofence receiver (flush on exit) — one implementation, three callers.
 */
object PresenceGeofencer {
  const val GEOFENCE_ID = "myaza-kyc-presence"

  private fun pendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, PresenceGeofenceReceiver::class.java)
    val mutable =
      if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
    return PendingIntent.getBroadcast(
      context, 4471, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutable,
    )
  }

  /** Registers the fence. The caller has already obtained the always
   *  permission Dart-side; a SecurityException here means it was revoked
   *  since, which reports as a plain failure. */
  @SuppressLint("MissingPermission")
  fun arm(context: Context, config: PresenceStore.Config, onDone: (Boolean) -> Unit) {
    try {
      val fence = Geofence.Builder()
        .setRequestId(GEOFENCE_ID)
        .setCircularRegion(config.lat, config.lng, config.radius.toFloat())
        .setExpirationDuration(Geofence.NEVER_EXPIRE)
        .setTransitionTypes(
          Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT,
        )
        .build()
      val request = GeofencingRequest.Builder()
        // Being at home when the fence arms should stamp immediately.
        .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
        .addGeofence(fence)
        .build()
      LocationServices.getGeofencingClient(context)
        .addGeofences(request, pendingIntent(context))
        .addOnSuccessListener { onDone(true) }
        .addOnFailureListener { onDone(false) }
    } catch (_: Exception) {
      onDone(false)
    }
  }

  fun disarm(context: Context) {
    try {
      LocationServices.getGeofencingClient(context).removeGeofences(pendingIntent(context))
    } catch (_: Exception) {
      // Not armed, or play services absent — either way, disarmed.
    }
  }

  /**
   * Posts the pending queue. Blocking HTTP on purpose — every caller is
   * already off the main thread (a receiver's goAsync worker or the channel
   * handler's executor). The server ingest is idempotent per (watch, day,
   * source) and MERGES, so a flush that half-landed is safe to retry whole.
   */
  fun flushQueue(store: PresenceStore) {
    val config = store.loadConfig() ?: return
    val pending = store.pendingQueue()
    if (pending.length() == 0) return
    val body = JSONObject()
      .put("externalUserId", config.externalUserId)
      .put("observations", sourcedGeofence(pending))
    var connection: HttpURLConnection? = null
    try {
      connection = URL("${config.baseUrl}/api/kyc/address/observations")
        .openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.connectTimeout = 8000
      connection.readTimeout = 8000
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.apiKey}")
      OutputStreamWriter(connection.outputStream).use { it.write(body.toString()) }
      if (connection.responseCode in 200..299) store.clearQueue()
    } catch (_: Exception) {
      // Best-effort: the queue is kept and the next transition retries it.
    } finally {
      connection?.disconnect()
    }
  }

  private fun sourcedGeofence(queue: JSONArray): JSONArray {
    val out = JSONArray()
    for (i in 0 until queue.length()) {
      val o = queue.getJSONObject(i)
      val wire = JSONObject()
        .put("day", o.getString("day"))
        .put("source", "geofence")
        .put("dwellMinutes", o.getInt("dwellMinutes"))
        .put("nightPresent", o.getBoolean("nightPresent"))
        .put("samples", o.getInt("samples"))
      // A mocked fix's day rides its flag through to the server.
      o.optJSONObject("integrity")?.let { wire.put("integrity", it) }
      out.put(wire)
    }
    return out
  }
}
