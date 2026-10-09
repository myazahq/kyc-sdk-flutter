import Flutter
import Foundation

/// Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
/// Dart owns the permission escalation, but the step up to "Always" is asked
/// here (PresenceAlwaysPermission): geolocator never asks for it on iOS. The
/// rest of this side persists the reporter config and arms/disarms the region.
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
    // Registration is only accepted while the app finishes launching, which
    // is when plugins register. A no-op unless the host opted in.
    PresenceMonitor.shared.registerCheckInTask()
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
          PresenceMonitor.shared.scheduleCheckIns()
        } else {
          PresenceStore.armed = false
        }
        result(ok)
      }
    case "presenceCheckIn":
      // The Dart reporter saw an inside fix on app open. iOS confirms it with
      // its own region state rather than trusting the coordinates twice.
      PresenceMonitor.shared.requestCheckIn()
      result(PresenceStore.armed)
    case "disablePresence":
      PresenceMonitor.shared.cancelCheckIns()
      PresenceMonitor.shared.disarm()
      PresenceStore.clear()
      result(nil)
    case "requestAlwaysLocation":
      PresenceAlwaysPermission.shared.request { word in result(word) }
    case "isPresenceArmed":
      result(PresenceMonitor.shared.isArmed)
    case "presenceStay":
      // The open stay, for the host to show. Nil with no stay open.
      guard PresenceStore.armed, let enterAt = PresenceStore.enterAt else {
        result(nil)
        return
      }
      result([
        "since": PresenceStore.stayStart ?? enterAt,
        "nextReportAt": PresenceFold.nextCheckpointAt(
          enterAt: enterAt, stayStart: PresenceStore.stayStart) as Any,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
