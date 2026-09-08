package co.myazahq.kyc

import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Pure maths for the background presence tier: fold one geofence dwell span
 * into per-local-day aggregates. LINE-FOR-LINE mirror of the RN SDK's
 * presence/background-math.ts and the iOS PresenceFold.swift — all three are
 * pinned to test/presence_fold_vectors.json (PresenceFoldTest.kt here), which
 * is why this is integer arithmetic on an EXPLICIT east-positive UTC offset
 * rather than java.time: identical inputs must fold identically in every
 * language, and minSdk 21 predates java.time anyway. The offset is captured
 * once per fold, a fixed-offset approximation that ignores a DST transition
 * inside one span; parity is worth more than that edge.
 */
object PresenceFold {
  /** A missed EXIT must not fabricate days of dwell: one span credits 24h at most. */
  const val MAX_SPAN_MS: Long = 24L * 60 * 60 * 1000

  private const val DAY_MS: Long = 24L * 60 * 60 * 1000
  private const val HOUR_MS: Long = 60L * 60 * 1000
  private const val NIGHT_END_H = 6
  private const val NIGHT_START_H = 20

  data class DayAggregate(val day: String, val dwellMinutes: Int, val nightPresent: Boolean)

  /** Howard Hinnant's civil_from_days: day index since 1970-01-01 → YYYY-MM-DD. */
  fun civilFromDays(z: Long): String {
    val zz = z + 719468
    val era = Math.floorDiv(zz, 146097L)
    val doe = zz - era * 146097
    val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    val y = yoe + era * 400
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    val mp = (5 * doy + 2) / 153
    val d = doy - (153 * mp + 2) / 5 + 1
    val m = if (mp < 10) mp + 3 else mp - 9
    val year = if (m <= 2) y + 1 else y
    return String.format("%04d-%02d-%02d", year, m, d)
  }

  fun foldSpanIntoDays(enterMs: Long, exitMs: Long, offsetMinutes: Int): List<DayAggregate> {
    if (exitMs <= enterMs) return emptyList()
    val offsetMs = offsetMinutes * 60_000L
    val cappedExit = minOf(exitMs, enterMs + MAX_SPAN_MS)

    val out = mutableListOf<DayAggregate>()
    var cursor = enterMs
    while (cursor < cappedExit) {
      val shifted = cursor + offsetMs
      val dayIndex = Math.floorDiv(shifted, DAY_MS)
      // The real-clock moment this local day ends.
      val dayEnd = (dayIndex + 1) * DAY_MS - offsetMs
      val sliceEnd = minOf(dayEnd, cappedExit)
      // Night = [00:00, 06:00) plus [20:00, 24:00) of this local day. Exact
      // interval overlap, no sampling, so all three languages agree at the
      // boundaries: a slice ENDING exactly at 20:00 has not touched the night.
      val dayStartShifted = dayIndex * DAY_MS
      val nightPresent =
        shifted < dayStartShifted + NIGHT_END_H * HOUR_MS ||
          sliceEnd + offsetMs > dayStartShifted + NIGHT_START_H * HOUR_MS
      out.add(
        DayAggregate(
          day = civilFromDays(dayIndex),
          dwellMinutes = max(1, ((sliceEnd - cursor).toDouble() / 60_000.0).roundToInt()),
          nightPresent = nightPresent,
        ),
      )
      cursor = sliceEnd
    }
    return out
  }
}
