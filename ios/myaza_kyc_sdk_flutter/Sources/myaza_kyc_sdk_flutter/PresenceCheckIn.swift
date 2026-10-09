import BackgroundTasks
import Foundation

/// "Still here" check-ins for the background presence tier. Region monitoring
/// only speaks when the person crosses the edge, so a stay was credited when
/// they LEFT: someone who hardly leaves home produced no background evidence,
/// and one exit the OS dropped capped a multi-day stay at its first 24 hours.
///
/// A check-in is iOS confirming the phone is inside (didDetermineState after
/// requestState). It happens on every launch or relaunch, when the Dart
/// reporter sees an inside fix on app open, and, when the HOST opts in, on a
/// periodic background refresh. Mirrors the RN SDK's presence/checkin.ts and
/// Android's PresenceCheckInWorker.
extension PresenceMonitor {
  /// The background refresh identifier. The host opts in by listing it under
  /// BGTaskSchedulerPermittedIdentifiers and adding the `fetch` background
  /// mode; without both nothing is registered (registering an undeclared
  /// identifier would crash the app at launch).
  static let checkInTaskId = "co.myazahq.kyc.presence.checkin"
  private static let checkInIntervalS: TimeInterval = 2 * 60 * 60

  /// Record a confirmed-inside reading: no open stay opens one; a stay open
  /// long enough is folded so far, queued, flushed and restarted.
  func recordCheckIn(atMs: Int64) {
    guard PresenceStore.armed else { return }
    let offsetMinutes = TimeZone.current.secondsFromGMT(
      for: Date(timeIntervalSince1970: Double(atMs) / 1000)
    ) / 60
    let out = PresenceFold.checkpointStay(
      enterAt: PresenceStore.enterAt, atMs: atMs, offsetMinutes: offsetMinutes,
      stayStart: PresenceStore.stayStart
    )
    PresenceStore.enterAt = out.enterAt
    PresenceStore.stayStart = out.stayStart
    if out.days.isEmpty { return }
    PresenceStore.queueDays(out.days)
    flushQueue()
  }

  static var hostAllowsCheckIns: Bool {
    let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    return (ids ?? []).contains(checkInTaskId) && (modes ?? []).contains("fetch")
  }

  /// Called once from plugin registration, which runs while the app finishes
  /// launching (the only time BGTaskScheduler accepts a registration).
  func registerCheckInTask() {
    guard PresenceMonitor.hostAllowsCheckIns else { return }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: PresenceMonitor.checkInTaskId, using: nil) {
      task in
      self.scheduleCheckIns()
      self.requestCheckIn()
      // requestState answers within moments; give the answer and its flush a
      // few seconds, well inside the refresh budget.
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        task.setTaskCompleted(success: true)
      }
      task.expirationHandler = { task.setTaskCompleted(success: false) }
    }
  }

  /// Ask iOS for the next refresh. iOS decides when it runs, usually around
  /// how often the person uses the app, so this narrows the gap rather than
  /// closing it on a schedule.
  func scheduleCheckIns() {
    guard PresenceMonitor.hostAllowsCheckIns, PresenceStore.armed else { return }
    let request = BGAppRefreshTaskRequest(identifier: PresenceMonitor.checkInTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: nextCheckInDelayS())
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Ask for the refresh just after the open stay becomes recordable (five
  /// minutes past, so the run finds it due), never later than the usual two
  /// hours. With no stay open, the usual two hours.
  private func nextCheckInDelayS() -> TimeInterval {
    guard
      let due = PresenceFold.nextCheckpointAt(
        enterAt: PresenceStore.enterAt, stayStart: PresenceStore.stayStart)
    else { return PresenceMonitor.checkInIntervalS }
    let untilDue = Double(due) / 1000 - Date().timeIntervalSince1970 + 5 * 60
    return min(PresenceMonitor.checkInIntervalS, max(5 * 60, untilDue))
  }

  func cancelCheckIns() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: PresenceMonitor.checkInTaskId)
  }
}
