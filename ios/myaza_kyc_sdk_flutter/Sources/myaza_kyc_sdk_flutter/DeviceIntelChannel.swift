import Flutter
import Foundation

/// Device Intelligence, iOS half (`kyc_sdk_flutter/device_intel`). Serves the
/// mobile fingerprint additions of kyc-core docs/DEVICE_INTEL_WIRE.md:
///
///  - `stableId`: a random UUID kept in the Keychain (account
///    `device-stable-id`), so it survives an uninstall and reinstall.
///  - `integrity`: jailbreak / hook heuristics ([DeviceIntegrity]).
///  - `appAttestState` / `appAttest`: App Attest ([AppAttest]).
///
/// Play Integrity is Android-only and answers not-implemented here; Dart reads
/// that as "skip". Results are always delivered on the main thread.
final class DeviceIntelChannel: NSObject {
  private static let stableIdAccount = "device-stable-id"
  private let work = DispatchQueue(label: "co.myazahq.kyc.device_intel", qos: .utility)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/device_intel", binaryMessenger: registrar.messenger())
    let instance = DeviceIntelChannel()
    channel.setMethodCallHandler { call, result in instance.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
    switch call.method {
    case "stableId":
      work.async { reply(Self.stableId()) }
    case "integrity":
      work.async { reply(DeviceIntegrity.check()) }
    case "appAttestState":
      reply(AppAttest.state())
    case "appAttest":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let hash = args["clientDataHash"] as? FlutterStandardTypedData else {
        reply(nil)
        return
      }
      AppAttest.run(
        keyId: args["keyId"] as? String,
        clientDataHash: hash.data,
        attest: args["attest"] as? Bool ?? true,
        done: { reply($0) }
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Created once, then reused. Returned only when it is actually stored: an
  /// id that would change on the next launch is not a stable id.
  private static func stableId() -> String? {
    if let existing = KeychainItem.read(stableIdAccount) { return existing }
    let fresh = UUID().uuidString
    return KeychainItem.write(stableIdAccount, fresh) ? fresh : nil
  }
}
