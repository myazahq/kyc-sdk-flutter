import Flutter
import Foundation

/// Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
/// Dart owns the permission escalation (geolocator's two-step to "always");
/// this side only persists the reporter config and arms/disarms the region.
final class PresenceChannel: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/presence",
      binaryMessenger: registrar.messenger()
    )
    let instance = PresenceChannel()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    // A relaunch for a region event lands here before any Dart runs: stand
    // the delegate up again so Core Location has somewhere to deliver.
    PresenceMonitor.shared.reattachIfArmed()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enablePresence":
      guard let args = call.arguments as? [String: Any],
            let lat = args["lat"] as? Double,
            let lng = args["lng"] as? Double,
            let baseUrl = args["baseUrl"] as? String,
            let apiKey = args["apiKey"] as? String,
            let externalUserId = args["externalUserId"] as? String
      else {
        result(false)
        return
      }
      let config = PresenceStore.Config(
        lat: lat, lng: lng,
        radius: (args["radius"] as? NSNumber)?.doubleValue ?? 250,
        baseUrl: baseUrl, apiKey: apiKey, externalUserId: externalUserId
      )
      PresenceMonitor.shared.arm(config: config) { ok in
        if ok {
          PresenceStore.saveConfig(config)
        } else {
          PresenceStore.armed = false
        }
        result(ok)
      }
    case "disablePresence":
      PresenceMonitor.shared.disarm()
      PresenceStore.clear()
      result(nil)
    case "isPresenceArmed":
      result(PresenceMonitor.shared.isArmed)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
