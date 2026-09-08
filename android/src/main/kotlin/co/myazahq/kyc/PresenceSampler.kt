package co.myazahq.kyc

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure state machine for the foreground-service tier. A geofence hands us
 * ENTER/EXIT moments; a periodic location sample hands us POSITIONS, and the
 * job here is to turn positions back into the same enter/exit spans the
 * geofence tier folds, on the SAME stored enterAt, so the two tiers
 * cooperate on one state rather than double-counting a stay:
 *
 *   inside,  no open stay  → open one (stamp enterAt)
 *   inside,  open stay     → nothing (the fence or an earlier sample did it)
 *   outside, open stay     → close it: fold the span into per-day aggregates
 *   outside, no open stay  → nothing (absence is never evidence)
 *   mocked                 → report the day FLAGGED, never open a stay
 *
 * Mirrors the RN SDK's presence/sampler.ts — keep the two in lockstep.
 */
object PresenceSampler {
  private const val EARTH_RADIUS_M = 6_371_000.0
  private const val DAY_MS: Long = 24L * 60 * 60 * 1000
  private const val HOUR_MS: Long = 60L * 60 * 1000

  data class Fix(
    val lat: Double,
    val lng: Double,
    val accuracy: Double?,
    val timestamp: Long,
    val mocked: Boolean?,
  )

  /** A mocked fix's day: reported flagged, with no dwell. */
  data class Flagged(val day: String, val nightPresent: Boolean)

  data class Result(
    val enterAt: Long?,
    val days: List<PresenceFold.DayAggregate>,
    val flagged: List<Flagged>,
  )

  fun haversineMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
    val rad = { d: Double -> d * Math.PI / 180.0 }
    val dLat = rad(lat2 - lat1)
    val dLng = rad(lng2 - lng1)
    val a = sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * EARTH_RADIUS_M * asin(min(1.0, sqrt(a)))
  }

  /** The server's at-address rule: 250 m, widened to the fix's reported
   *  accuracy, capped at 1 km. The Dart reporter applies the same rule. */
  fun insideFence(pinLat: Double, pinLng: Double, fix: Fix): Boolean {
    val radius = min(1000.0, maxOf(250.0, fix.accuracy ?: 0.0))
    return haversineMeters(pinLat, pinLng, fix.lat, fix.lng) <= radius
  }

  /** The local calendar day + night flag for a moment, on the same explicit
   *  offset arithmetic as the fold, so a flagged day and a folded day can
   *  never disagree about which day it was. Night = 20:00 to 05:59. */
  fun localDay(timestamp: Long, offsetMinutes: Int): Flagged {
    val shifted = timestamp + offsetMinutes * 60_000L
    val dayIndex = Math.floorDiv(shifted, DAY_MS)
    val hour = (Math.floorMod(shifted, DAY_MS) / HOUR_MS).toInt()
    return Flagged(PresenceFold.civilFromDays(dayIndex), hour >= 20 || hour < 6)
  }

  /** Apply a batch of fixes (any order; sorted here) to the open-stay state. */
  fun apply(
    pinLat: Double,
    pinLng: Double,
    fixes: List<Fix>,
    enterAt: Long?,
    offsetMinutes: Int,
  ): Result {
    var open = enterAt
    val days = mutableListOf<PresenceFold.DayAggregate>()
    val flagged = mutableListOf<Flagged>()
    for (fix in fixes.sortedBy { it.timestamp }) {
      if (fix.mocked == true) {
        flagged.add(localDay(fix.timestamp, offsetMinutes))
        continue
      }
      if (insideFence(pinLat, pinLng, fix)) {
        if (open == null) open = fix.timestamp
        continue
      }
      val enteredAt = open ?: continue
      days.addAll(PresenceFold.foldSpanIntoDays(enteredAt, fix.timestamp, offsetMinutes))
      open = null
    }
    return Result(open, days, flagged)
  }
}
