package co.myazahq.kyc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The foreground-service tier's state machine: positions in, the geofence
 * tier's enter/exit spans out, on the SAME open-stay state. A port of the RN
 * SDK's presenceSampler.test.ts — keep the two in lockstep.
 */
class PresenceSamplerTest {
  private val pinLat = 6.4281
  private val pinLng = 3.4219
  private val farLat = 6.4461 // ~2 km north
  private val lagos = 60 // east-positive minutes

  /** A Lagos wall-clock moment as epoch ms (2026-09-DD hh:mm, UTC+1). */
  private fun at(day: Int, hour: Int, minute: Int = 0): Long {
    val daysSinceEpoch = 20697L + (day - 1) // 2026-09-01 is day 20697 since the epoch
    val localMs = daysSinceEpoch * 86_400_000L + hour * 3_600_000L + minute * 60_000L
    return localMs - lagos * 60_000L
  }

  private fun fix(lat: Double, lng: Double, ts: Long, mocked: Boolean? = false) =
    PresenceSampler.Fix(lat, lng, 10.0, ts, mocked)

  @Test
  fun opensAStayOnTheFirstInsideFixAndHoldsIt() {
    val r = PresenceSampler.apply(pinLat, pinLng, listOf(fix(pinLat, pinLng, at(3, 9))), null, lagos)
    assertEquals(at(3, 9), r.enterAt)
    assertTrue(r.days.isEmpty())
    val again = PresenceSampler.apply(pinLat, pinLng, listOf(fix(pinLat, pinLng, at(3, 12))), r.enterAt, lagos)
    assertEquals(at(3, 9), again.enterAt)
  }

  @Test
  fun closesAStayOnTheFirstOutsideFixAndFoldsTheSpan() {
    val r = PresenceSampler.apply(pinLat, pinLng, listOf(fix(farLat, pinLng, at(3, 11, 30))), at(3, 9), lagos)
    assertNull(r.enterAt)
    assertEquals(listOf(PresenceFold.DayAggregate("2026-09-03", 150, false)), r.days)
  }

  @Test
  fun respectsAStayTheGeofenceTierAlreadyOpened() {
    val r = PresenceSampler.apply(pinLat, pinLng, listOf(fix(farLat, pinLng, at(4, 7))), at(3, 22), lagos)
    assertEquals(listOf("2026-09-03", "2026-09-04"), r.days.map { it.day })
    assertTrue(r.days.all { it.nightPresent })
  }

  @Test
  fun isAbsenceBlind() {
    val r = PresenceSampler.apply(
      pinLat, pinLng, listOf(fix(farLat, pinLng, at(3, 9)), fix(farLat, pinLng, at(3, 18))), null, lagos,
    )
    assertNull(r.enterAt)
    assertTrue(r.days.isEmpty())
    assertTrue(r.flagged.isEmpty())
  }

  @Test
  fun sortsABatchByTimeBeforeApplyingIt() {
    val r = PresenceSampler.apply(
      pinLat, pinLng, listOf(fix(farLat, pinLng, at(3, 12)), fix(pinLat, pinLng, at(3, 9))), null, lagos,
    )
    assertNull(r.enterAt)
    assertEquals(180, r.days.first().dwellMinutes)
  }

  @Test
  fun reportsAMockedFixFlaggedAndNeverOpensAStayOnIt() {
    val r = PresenceSampler.apply(pinLat, pinLng, listOf(fix(pinLat, pinLng, at(3, 22), mocked = true)), null, lagos)
    assertNull(r.enterAt)
    assertTrue(r.days.isEmpty())
    assertEquals(listOf(PresenceSampler.Flagged("2026-09-03", true)), r.flagged)
  }

  @Test
  fun localDayAgreesWithTheFoldAtTheNightBoundary() {
    // 19:59 is day; 20:00 is night — the same edge the fold draws.
    assertEquals(PresenceSampler.Flagged("2026-09-03", false), PresenceSampler.localDay(at(3, 19, 59), lagos))
    assertEquals(PresenceSampler.Flagged("2026-09-03", true), PresenceSampler.localDay(at(3, 20), lagos))
    assertEquals(PresenceSampler.Flagged("2026-09-04", true), PresenceSampler.localDay(at(4, 2), lagos))
  }
}
