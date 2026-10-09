import CoreLocation
import UIKit

/// Asks iOS for "Always" location, the permission the background presence
/// tier needs.
///
/// This is native on purpose. The geolocator plugin's request returns at once
/// when any decision already exists, and with both usage strings declared it
/// only ever asks for "While Using", so from Dart nothing reached
/// `requestAlwaysAuthorization` and iOS never showed the "Change to Always
/// Allow" prompt: background presence could only be switched on by hand in
/// Settings.
///
/// iOS shows that prompt ONCE per install. After that the call is silent, so
/// "no prompt appeared" is detected (the app never left the foreground) and
/// the current status is returned for the host to send the person to Settings.
final class PresenceAlwaysPermission: NSObject, CLLocationManagerDelegate {
  static let shared = PresenceAlwaysPermission()

  private var manager: CLLocationManager?
  private var completion: ((String) -> Void)?
  private var promptShown = false
  private var observers: [NSObjectProtocol] = []

  /// How long to wait for iOS to put a prompt up before deciding it will not.
  private static let promptWait: TimeInterval = 1.5

  static func word(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whileInUse"
    case .denied, .restricted: return "denied"
    case .notDetermined: return "undetermined"
    @unknown default: return "undetermined"
    }
  }

  private func status(_ manager: CLLocationManager) -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) { return manager.authorizationStatus }
    return CLLocationManager.authorizationStatus()
  }

  func request(completion: @escaping (String) -> Void) {
    DispatchQueue.main.async {
      // One request at a time: a second caller gets the current answer.
      let manager = self.manager ?? CLLocationManager()
      self.manager = manager
      let current = self.status(manager)
      let declared = Bundle.main.object(
        forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil
      if self.completion != nil || !declared
        || current == .authorizedAlways || current == .denied || current == .restricted {
        completion(Self.word(current))
        return
      }
      self.completion = completion
      self.promptShown = false
      manager.delegate = self
      let center = NotificationCenter.default
      self.observers = [
        // A system prompt takes the app out of the active state.
        center.addObserver(
          forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.promptShown = true },
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
          // The choice is applied a moment after the prompt closes.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.finish() }
        },
      ]
      manager.requestAlwaysAuthorization()
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.promptWait) { [weak self] in
        guard let self = self, !self.promptShown else { return }
        self.finish()
      }
    }
  }

  private func finish() {
    guard let completion = completion, let manager = manager else { return }
    self.completion = nil
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    completion(Self.word(status(manager)))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if status(manager) == .authorizedAlways { finish() }
  }
}
