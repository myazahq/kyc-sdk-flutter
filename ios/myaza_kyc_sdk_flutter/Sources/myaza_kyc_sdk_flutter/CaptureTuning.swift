import AVFoundation
import Flutter
import UIKit

/// Holds the camera and the screen steady for the duration of a flash-liveness
/// sequence.
///
/// Flash liveness measures how the face's colour shifts when the screen paints
/// a known colour. Two automatic systems work directly against that:
///
///  • AUTO WHITE BALANCE — its entire purpose is to cancel colour casts. Paint
///    the screen red and AWB decides the scene is too warm and corrects back
///    toward neutral, erasing the signal being measured. This is the single
///    most damaging one, and it is why locking matters more than any tuning.
///  • AUTO EXPOSURE — more light reaches the sensor, gain drops, and the
///    measured shift shrinks.
///
/// Screen brightness is the other half: the display IS the light source. At 20%
/// brightness, or outdoors, no flash is measurable — and an unmeasurable
/// sequence is scored inconclusive, which passes. So brightness is not polish;
/// it decides whether the check does anything at all.
///
/// Both are restored by `restore`, which is idempotent so the Dart side can
/// call it from a `finally` without tracking whether locking succeeded.
///
/// The screen has a second holder: the bright-screen liveness
/// (`setBrightness` / `restoreBrightness`) keeps the screen at full for as long
/// as the selfie camera is on, around the flash. Each holder releases only
/// itself; the person's own brightness comes back when the LAST one lets go,
/// so a flash ending never dims the lit screen and vice versa.
public class CaptureTuning: NSObject, FlutterPlugin {
  private static let flashHolder = "flash"
  private static let screenHolder = "screen"

  /// The brightness before the first holder raised it; nil when none holds.
  private var previousBrightness: CGFloat?
  private var brightnessHolders = Set<String>()
  private var lockedDevice: AVCaptureDevice?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/capture_tuning",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(CaptureTuning(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginFlash":
      let brightness = (call.arguments as? [String: Any])?["brightness"] as? Double
      begin(brightness: brightness ?? 1.0)
      result(nil)
    case "restore":
      restore()
      result(nil)
    case "setBrightness":
      let brightness = (call.arguments as? [String: Any])?["brightness"] as? Double
      raiseBrightness(holder: Self.screenHolder, to: brightness ?? 1.0)
      result(nil)
    case "restoreBrightness":
      releaseBrightness(holder: Self.screenHolder)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(brightness: Double) {
    // Screen brightness must be raised BEFORE sampling starts and then held
    // flat. Ramping it mid-sequence would make our own UI a luminance shift
    // inside the baseline-vs-lit comparison — measuring ourselves, not the face.
    raiseBrightness(holder: Self.flashHolder, to: brightness)

    lockCamera()
  }

  /// Raises the screen for [holder], saving the person's own value the first
  /// time anyone raises it. App-scoped: UIScreen brightness, never Settings.
  private func raiseBrightness(holder: String, to brightness: Double) {
    if previousBrightness == nil {
      previousBrightness = UIScreen.main.brightness
    }
    brightnessHolders.insert(holder)
    UIScreen.main.brightness = CGFloat(max(0.0, min(1.0, brightness)))
  }

  /// Lets go for [holder]; the saved value returns once nobody holds the
  /// screen. Idempotent.
  private func releaseBrightness(holder: String) {
    brightnessHolders.remove(holder)
    guard brightnessHolders.isEmpty, let previous = previousBrightness else { return }
    UIScreen.main.brightness = previous
    previousBrightness = nil
  }

  /// Locks white balance and exposure at their CURRENT (ambient) values, so the
  /// baseline and the lit frames are measured on the same footing.
  private func lockCamera() {
    guard lockedDevice == nil, let device = frontCamera() else { return }
    do {
      try device.lockForConfiguration()
      if device.isWhiteBalanceModeSupported(.locked) {
        device.whiteBalanceMode = .locked
      }
      if device.isExposureModeSupported(.locked) {
        device.exposureMode = .locked
      }
      device.unlockForConfiguration()
      lockedDevice = device
    } catch {
      // A device busy elsewhere just stays automatic — a weaker signal, not a
      // broken capture. Never fail the flow over tuning.
    }
  }

  private func restore() {
    releaseBrightness(holder: Self.flashHolder)

    guard let device = lockedDevice else { return }
    lockedDevice = nil
    do {
      try device.lockForConfiguration()
      if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
        device.whiteBalanceMode = .continuousAutoWhiteBalance
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
    } catch {
      // Leaving the camera locked would degrade the selfie that follows, but
      // there is no recovery here beyond the session teardown that comes next.
    }
  }

  /// The liveness camera. Matches what the camera plugin selects for a
  /// front-facing lens; locking a device that isn't in an active session is
  /// harmless.
  private func frontCamera() -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: .front
    ).devices.first
  }
}
