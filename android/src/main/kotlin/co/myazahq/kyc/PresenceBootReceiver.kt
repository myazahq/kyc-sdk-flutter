package co.myazahq.kyc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Geofences do not survive a reboot; the armed config does. Re-registers the
 * fence after restart so always-on monitoring keeps running without anyone
 * opening the app. Inert unless a config was armed — a host that never
 * enables the background tier gets a receiver that reads one preference and
 * returns.
 */
class PresenceBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
    val store = PresenceStore(context)
    if (!store.armed) return
    val config = store.loadConfig() ?: return
    val pending = goAsync()
    PresenceGeofencer.arm(context, config) { ok ->
      // A failed re-arm (permission revoked while off) leaves armed=true so
      // the next app open can surface the downgrade via presenceStatus().
      if (!ok) store.enterAt = null
      // The foreground-service tier restarts too: a reboot is an exemption
      // from the background-start restriction, and the service rebuilds its
      // notification from the persisted config with no Dart running.
      if (store.serviceEnabled) PresenceForegroundService.start(context)
      pending.finish()
    }
  }
}
