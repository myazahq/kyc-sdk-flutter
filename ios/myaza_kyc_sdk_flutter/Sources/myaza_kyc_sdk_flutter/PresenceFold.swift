import Foundation

/// Pure maths for the background presence tier: fold one geofence dwell span
/// into per-local-day aggregates. LINE-FOR-LINE mirror of the RN SDK's
/// presence/background-math.ts and Android's PresenceFold.kt — all three are
/// pinned to test/presence_fold_vectors.json (PresenceFoldTests.swift here),
/// which is why this is integer arithmetic on an EXPLICIT east-positive UTC
/// offset rather than Calendar/TimeZone APIs: identical inputs must fold
/// identically in every language. The offset is captured once per fold, a
/// fixed-offset approximation that ignores a DST transition inside one span;
/// parity is worth more than that edge.
enum PresenceFold {
  /// A missed EXIT must not fabricate days of dwell: one span credits 24h at most.
  static let maxSpanMs: Int64 = 24 * 60 * 60 * 1000

  private static let dayMs: Int64 = 24 * 60 * 60 * 1000
  private static let hourMs: Int64 = 60 * 60 * 1000
  private static let nightEndH: Int64 = 6
  private static let nightStartH: Int64 = 20

  struct DayAggregate: Equatable {
    let day: String
    let dwellMinutes: Int
    let nightPresent: Bool
  }

  private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
  }

  /// Howard Hinnant's civil_from_days: day index since 1970-01-01 → YYYY-MM-DD.
  static func civilFromDays(_ z: Int64) -> String {
    let zz = z + 719468
    let era = floorDiv(zz, 146097)
    let doe = zz - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    let year = m <= 2 ? y + 1 : y
    return String(format: "%04d-%02d-%02d", year, m, d)
  }

  static func foldSpanIntoDays(enterMs: Int64, exitMs: Int64, offsetMinutes: Int) -> [DayAggregate] {
    if exitMs <= enterMs { return [] }
    let offsetMs = Int64(offsetMinutes) * 60_000
    let cappedExit = min(exitMs, enterMs + maxSpanMs)

    var out: [DayAggregate] = []
    var cursor = enterMs
    while cursor < cappedExit {
      let shifted = cursor + offsetMs
      let dayIndex = floorDiv(shifted, dayMs)
      // The real-clock moment this local day ends.
      let dayEnd = (dayIndex + 1) * dayMs - offsetMs
      let sliceEnd = min(dayEnd, cappedExit)
      // Night = [00:00, 06:00) plus [20:00, 24:00) of this local day. Exact
      // interval overlap, no sampling, so all three languages agree at the
      // boundaries: a slice ENDING exactly at 20:00 has not touched the night.
      let dayStartShifted = dayIndex * dayMs
      let nightPresent =
        shifted < dayStartShifted + nightEndH * hourMs ||
        sliceEnd + offsetMs > dayStartShifted + nightStartH * hourMs
      out.append(
        DayAggregate(
          day: civilFromDays(dayIndex),
          dwellMinutes: max(1, Int((Double(sliceEnd - cursor) / 60_000.0).rounded())),
          nightPresent: nightPresent
        )
      )
      cursor = sliceEnd
    }
    return out
  }

  /// How long an open stay may run before a confirmed "still here" reading
  /// records it. Without check-ins a stay was credited only when the person
  /// left, so someone who hardly leaves home produced no background evidence,
  /// and one lost exit capped a multi-day stay at its first 24 hours.
  ///
  /// The FIRST check-in of a stay comes at 35 minutes, just past the server's
  /// default 30-minute dwell floor, so a day is credited soon after the
  /// person gets home. Later ones wait three hours: the server keeps the
  /// LONGEST slice per day, so short slices all day would never satisfy an
  /// organisation whose floor is set above them.
  static let firstCheckpointMs: Int64 = 35 * 60 * 1000
  static let checkpointMs: Int64 = 3 * 60 * 60 * 1000

  /// `stayStart` is when the person arrived; check-ins never move it.
  struct Checkpoint: Equatable {
    let enterAt: Int64
    let stayStart: Int64
    let days: [DayAggregate]
  }

  /// The interval the open stay is waiting on: the short one until something
  /// has recorded it (no start on file, or a start that is the stay's own).
  static func checkpointInterval(enterAt: Int64, stayStart: Int64?) -> Int64 {
    guard let start = stayStart, start < enterAt else { return firstCheckpointMs }
    return checkpointMs
  }

  /// When the next check-in can record the open stay; nil with none open.
  static func nextCheckpointAt(enterAt: Int64?, stayStart: Int64?) -> Int64? {
    enterAt.map { $0 + checkpointInterval(enterAt: $0, stayStart: stayStart) }
  }

  /// Apply a CONFIRMED-INSIDE reading at `atMs`. No open stay opens one; a
  /// stay open at least its interval is folded up to `atMs` and restarted
  /// there; anything else is unchanged. Mirrors checkpointStay in the RN
  /// SDK's background-math.ts and PresenceFold.kt, pinned to the same vectors.
  static func checkpointStay(
    enterAt: Int64?, atMs: Int64, offsetMinutes: Int, stayStart: Int64? = nil
  ) -> Checkpoint {
    guard let enterAt = enterAt else { return Checkpoint(enterAt: atMs, stayStart: atMs, days: []) }
    let start = stayStart ?? enterAt
    if atMs - enterAt < checkpointInterval(enterAt: enterAt, stayStart: stayStart) {
      return Checkpoint(enterAt: enterAt, stayStart: start, days: [])
    }
    return Checkpoint(
      enterAt: atMs, stayStart: start,
      days: foldSpanIntoDays(enterMs: enterAt, exitMs: atMs, offsetMinutes: offsetMinutes)
    )
  }
}
