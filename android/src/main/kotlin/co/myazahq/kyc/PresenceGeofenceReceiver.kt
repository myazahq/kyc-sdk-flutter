package co.myazahq.kyc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import java.util.TimeZone
import kotlin.concurrent.thread

/**
 * The OS wakes this on fence transitions, app killed or not. ENTER stamps a
 * timestamp; EXIT folds the dwell span into per-day aggregates and flushes
 * them — the only data that ever leaves the device. Mirrors the RN geofence
 * task in presence/background.ts.
 */
class PresenceGeofenceReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val event = GeofencingEvent.fromIntent(intent) ?: return
    if (event.hasError()) return
    val store = PresenceStore(context)
    if (!store.armed) return
    when (event.geofenceTransition) {
      Geofence.GEOFENCE_TRANSITION_ENTER -> {
        store.enterAt = System.currentTimeMillis()
      }
      Geofence.GEOFENCE_TRANSITION_EXIT -> {
        val enteredAt = store.enterAt ?: return
        store.enterAt = null
        val now = System.currentTimeMillis()
        val offsetMinutes = TimeZone.getDefault().getOffset(enteredAt) / 60_000
        val days = PresenceFold.foldSpanIntoDays(enteredAt, now, offsetMinutes)
        if (days.isEmpty()) return
        store.queueDays(days)
        // A receiver gets ~10s; goAsync buys the network call breathing room
        // and the queue survives if the flush loses the race anyway.
        val pending = goAsync()
        thread(name = "myaza-presence-flush") {
          try {
            PresenceGeofencer.flushQueue(store)
          } finally {
            pending.finish()
          }
        }
      }
    }
  }
}
