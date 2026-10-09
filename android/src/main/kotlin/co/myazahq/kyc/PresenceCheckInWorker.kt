package co.myazahq.kyc

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.Tasks
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * "Still here" check-ins for the background presence tier. A geofence only
 * speaks when the person crosses its edge, so a stay was credited when they
 * LEFT: someone who hardly leaves home produced no background evidence, and
 * one exit the OS dropped capped a multi-day stay at its first 24 hours.
 *
 * Every couple of hours (WorkManager decides exactly when), and once about
 * 40 minutes after the person arrives, this takes one low-power fix and hands it to the foreground-service tier's own state
 * machine (PresenceSampler), on the SAME stored enterAt: inside, the stay so
 * far is folded and restarted at the reading; outside with a stay open, it is
 * closed. Only per-day aggregates ever leave the device. It also re-arms a
 * fence a location toggle dropped. Mirrors the RN SDK's presence/checkin.ts.
 *
 * WorkManager is a library, not a permission: nothing here changes the host's
 * manifest or store review. It runs only after the host enabled the
 * background tier, which needs the background location grant already.
 */
class PresenceCheckInWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
  override fun doWork(): Result {
    val store = PresenceStore(applicationContext)
    if (!store.armed) return Result.success()
    val config = store.loadConfig() ?: return Result.success()
    if (!backgroundGranted(applicationContext)) return Result.success()
    val location = currentFix(applicationContext) ?: return Result.success()
    applyCheckIn(store, config, fromLocation(location))
    PresenceGeofencer.arm(applicationContext, config) { }
    return Result.success()
  }

  companion object {
    private const val WORK_NAME = "myaza-kyc-presence-checkin"
    private const val FIRST_WORK_NAME = "myaza-kyc-presence-checkin-first"
    private const val INTERVAL_HOURS = 2L
    /** Just past the 35-minute first check-in (PresenceFold), so the run
     *  that follows an arrival finds a stay long enough to record. */
    private const val FIRST_DELAY_MINUTES = 40L
    private const val FIX_TIMEOUT_S = 20L
    private const val LAST_KNOWN_MAX_AGE_MS = 15L * 60 * 1000

    fun schedule(context: Context) {
      try {
        val request = PeriodicWorkRequestBuilder<PresenceCheckInWorker>(INTERVAL_HOURS, TimeUnit.HOURS).build()
        WorkManager.getInstance(context.applicationContext)
          .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
      } catch (_: Exception) {
        // WorkManager unavailable: the fence and app-open check-ins still run.
      }
    }

    /**
     * One run shortly after an arrival, so the day is credited while the
     * person is still at home rather than at the next two-hourly run. A new
     * arrival replaces a run still waiting on the last one.
     */
    fun scheduleFirst(context: Context) {
      try {
        val request = OneTimeWorkRequestBuilder<PresenceCheckInWorker>()
          .setInitialDelay(FIRST_DELAY_MINUTES, TimeUnit.MINUTES)
          .build()
        WorkManager.getInstance(context.applicationContext)
          .enqueueUniqueWork(FIRST_WORK_NAME, ExistingWorkPolicy.REPLACE, request)
      } catch (_: Exception) {
        // WorkManager unavailable: the periodic run and app opens still check in.
      }
    }

    fun cancel(context: Context) {
      try {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(FIRST_WORK_NAME)
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(WORK_NAME)
      } catch (_: Exception) {
        // Not scheduled.
      }
    }

    /**
     * Apply one confirmed reading to the stay and flush. Shared with the
     * channel's app-open check-in, so both occasions follow one rule.
     * Blocking HTTP: every caller is off the main thread.
     */
    fun applyCheckIn(store: PresenceStore, config: PresenceStore.Config, fix: PresenceSampler.Fix) {
      val offsetMinutes = TimeZone.getDefault().getOffset(fix.timestamp) / 60_000
      val out = PresenceSampler.apply(
        config.lat, config.lng, listOf(fix), store.enterAt, offsetMinutes, store.stayStart,
      )
      store.enterAt = out.enterAt
      store.stayStart = out.stayStart
      if (out.days.isNotEmpty()) store.queueDays(out.days)
      for (f in out.flagged) store.queueFlagged(f.day, f.nightPresent)
      PresenceGeofencer.flushQueue(store)
    }

    private fun backgroundGranted(context: Context): Boolean {
      val permission =
        if (Build.VERSION.SDK_INT >= 29) Manifest.permission.ACCESS_BACKGROUND_LOCATION
        else Manifest.permission.ACCESS_FINE_LOCATION
      return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun currentFix(context: Context): Location? {
      val client = LocationServices.getFusedLocationProviderClient(context)
      val fresh = try {
        Tasks.await(
          client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null),
          FIX_TIMEOUT_S, TimeUnit.SECONDS,
        )
      } catch (_: Exception) {
        null
      }
      if (fresh != null) return fresh
      val known = try {
        Tasks.await(client.lastLocation, FIX_TIMEOUT_S, TimeUnit.SECONDS)
      } catch (_: Exception) {
        null
      }
      return known?.takeIf { System.currentTimeMillis() - it.time <= LAST_KNOWN_MAX_AGE_MS }
    }

    private fun fromLocation(l: Location) = PresenceSampler.Fix(
      lat = l.latitude,
      lng = l.longitude,
      accuracy = if (l.hasAccuracy()) l.accuracy.toDouble() else null,
      timestamp = l.time,
      mocked = if (Build.VERSION.SDK_INT >= 31) l.isMock else @Suppress("DEPRECATION") l.isFromMockProvider,
    )
  }
}
