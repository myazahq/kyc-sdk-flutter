import Foundation

/// Persistence for the background presence tier: the armed config, the open
/// ENTER timestamp, and the pending per-day queue. UserDefaults because the
/// relaunched-for-a-region-event process must read it before any Dart runs.
/// Only per-day aggregates are ever stored; a location trace never exists
/// anywhere. Mirrors Android's PresenceStore.kt and RN's background-store.ts.
struct PresenceStore {
  private static let configKey = "myaza_kyc_presence.config"
  private static let armedKey = "myaza_kyc_presence.armed"
  private static let enterAtKey = "myaza_kyc_presence.enterAt"
  private static let queueKey = "myaza_kyc_presence.queue"

  struct Config {
    let lat: Double
    let lng: Double
    let radius: Double
    let baseUrl: String
    let apiKey: String
    let externalUserId: String
  }

  static func saveConfig(_ config: Config) {
    let defaults = UserDefaults.standard
    defaults.set(
      [
        "lat": config.lat, "lng": config.lng, "radius": config.radius,
        "baseUrl": config.baseUrl, "apiKey": config.apiKey,
        "externalUserId": config.externalUserId,
      ] as [String: Any],
      forKey: configKey
    )
    defaults.set(true, forKey: armedKey)
  }

  static func loadConfig() -> Config? {
    guard let raw = UserDefaults.standard.dictionary(forKey: configKey),
          let lat = raw["lat"] as? Double, let lng = raw["lng"] as? Double,
          let baseUrl = raw["baseUrl"] as? String, let apiKey = raw["apiKey"] as? String,
          let externalUserId = raw["externalUserId"] as? String
    else { return nil }
    return Config(
      lat: lat, lng: lng, radius: raw["radius"] as? Double ?? 250,
      baseUrl: baseUrl, apiKey: apiKey, externalUserId: externalUserId
    )
  }

  static func clear() {
    let defaults = UserDefaults.standard
    [configKey, armedKey, enterAtKey, queueKey].forEach { defaults.removeObject(forKey: $0) }
  }

  static var armed: Bool {
    get { UserDefaults.standard.bool(forKey: armedKey) }
    set { UserDefaults.standard.set(newValue, forKey: armedKey) }
  }

  static var enterAt: Int64? {
    get {
      let value = UserDefaults.standard.object(forKey: enterAtKey) as? NSNumber
      return value.map { $0.int64Value }
    }
    set {
      if let value = newValue {
        UserDefaults.standard.set(NSNumber(value: value), forKey: enterAtKey)
      } else {
        UserDefaults.standard.removeObject(forKey: enterAtKey)
      }
    }
  }

  /// Merge fresh day aggregates into the queue: same day → sum dwell, OR
  /// night, sum samples. The RN tier's mergeIntoQueue, verbatim.
  static func queueDays(_ days: [PresenceFold.DayAggregate]) {
    var byDay: [String: [String: Any]] = [:]
    var order: [String] = []
    for entry in pendingQueue() {
      guard let day = entry["day"] as? String else { continue }
      byDay[day] = entry
      order.append(day)
    }
    for aggregate in days {
      if var prior = byDay[aggregate.day] {
        prior["dwellMinutes"] = (prior["dwellMinutes"] as? Int ?? 0) + aggregate.dwellMinutes
        prior["nightPresent"] = (prior["nightPresent"] as? Bool ?? false) || aggregate.nightPresent
        prior["samples"] = (prior["samples"] as? Int ?? 0) + 1
        byDay[aggregate.day] = prior
      } else {
        byDay[aggregate.day] = [
          "day": aggregate.day, "dwellMinutes": aggregate.dwellMinutes,
          "nightPresent": aggregate.nightPresent, "samples": 1,
        ]
        order.append(aggregate.day)
      }
    }
    UserDefaults.standard.set(order.compactMap { byDay[$0] }, forKey: queueKey)
  }

  static func pendingQueue() -> [[String: Any]] {
    (UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]]) ?? []
  }

  static func clearQueue() {
    UserDefaults.standard.removeObject(forKey: queueKey)
  }
}
