import CoreLocation
import Foundation
import UIKit

/// Region monitoring for the background presence tier. iOS relaunches the app
/// for region crossings even after termination; plugin registration re-creates
/// this monitor whenever an armed config exists, so the delegate is standing
/// when Core Location redelivers the event. ENTER stamps a timestamp; EXIT
/// folds the dwell span (PresenceFold) into per-day aggregates and flushes
/// them — the only data that ever leaves the device. Mirrors Android's
/// PresenceGeofenceReceiver + PresenceGeofencer.
final class PresenceMonitor: NSObject, CLLocationManagerDelegate {
  static let shared = PresenceMonitor()
  static let regionId = "myaza-kyc-presence"

  private var manager: CLLocationManager?

  /// Called from plugin registration: stand the delegate up again when a
  /// config is armed, so relaunch-delivered events have somewhere to land.
  func reattachIfArmed() {
    guard PresenceStore.armed, PresenceStore.loadConfig() != nil else { return }
    ensureManager()
  }

  private func ensureManager() {
    if manager == nil {
      // Core Location requires the manager be created on a run-loop thread.
      if Thread.isMainThread {
        manager = CLLocationManager()
        manager?.delegate = self
      } else {
        DispatchQueue.main.sync {
          self.manager = CLLocationManager()
          self.manager?.delegate = self
        }
      }
    }
  }

  func arm(config: PresenceStore.Config, completion: @escaping (Bool) -> Void) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      completion(false)
      return
    }
    ensureManager()
    guard let manager = manager else {
      completion(false)
      return
    }
    let radius = min(config.radius, manager.maximumRegionMonitoringDistance)
    let region = CLCircularRegion(
      center: CLLocationCoordinate2D(latitude: config.lat, longitude: config.lng),
      radius: radius,
      identifier: PresenceMonitor.regionId
    )
    region.notifyOnEntry = true
    region.notifyOnExit = true
    manager.startMonitoring(for: region)
    // Being at home when the fence arms should stamp immediately; iOS answers
    // via didDetermineState rather than a synthetic entry event.
    manager.requestState(for: region)
    completion(true)
  }

  func disarm() {
    ensureManager()
    guard let manager = manager else { return }
    for region in manager.monitoredRegions where region.identifier == PresenceMonitor.regionId {
      manager.stopMonitoring(for: region)
    }
  }

  var isArmed: Bool {
    ensureManager()
    guard PresenceStore.armed else { return false }
    return manager?.monitoredRegions.contains { $0.identifier == PresenceMonitor.regionId } ?? false
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    PresenceStore.enterAt = Int64(Date().timeIntervalSince1970 * 1000)
  }

  func locationManager(
    _ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion
  ) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    // The arm-time state answer: already inside → stamp, exactly like
    // Android's INITIAL_TRIGGER_ENTER. Never overwrite an open stamp.
    if state == .inside && PresenceStore.enterAt == nil {
      PresenceStore.enterAt = Int64(Date().timeIntervalSince1970 * 1000)
    }
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    guard let enteredAt = PresenceStore.enterAt else { return }
    PresenceStore.enterAt = nil
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let offsetMinutes = TimeZone.current.secondsFromGMT(
      for: Date(timeIntervalSince1970: Double(enteredAt) / 1000)
    ) / 60
    let days = PresenceFold.foldSpanIntoDays(enterMs: enteredAt, exitMs: now, offsetMinutes: offsetMinutes)
    if days.isEmpty { return }
    PresenceStore.queueDays(days)
    flushQueue()
  }

  /// Posts the pending queue. The relaunched-for-an-event process gets only
  /// seconds, so the network call runs under a background task. The server
  /// ingest is idempotent per (watch, day, source) and MERGES, so a flush
  /// that half-landed is safe to retry whole next time.
  func flushQueue() {
    guard let config = PresenceStore.loadConfig() else { return }
    let pending = PresenceStore.pendingQueue()
    if pending.isEmpty { return }
    let observations = pending.map { entry -> [String: Any] in
      [
        "day": entry["day"] as? String ?? "",
        "source": "geofence",
        "dwellMinutes": entry["dwellMinutes"] as? Int ?? 1,
        "nightPresent": entry["nightPresent"] as? Bool ?? false,
        "samples": entry["samples"] as? Int ?? 1,
      ]
    }
    guard let url = URL(string: "\(config.baseUrl)/api/kyc/address/observations"),
          let body = try? JSONSerialization.data(withJSONObject: [
            "externalUserId": config.externalUserId,
            "observations": observations,
          ])
    else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = body

    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    backgroundTask = UIApplication.shared.beginBackgroundTask {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    URLSession.shared.dataTask(with: request) { _, response, _ in
      if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
        PresenceStore.clearQueue()
      }
      if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
      }
    }.resume()
  }
}
