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
public class CaptureTuning: NSObject, FlutterPlugin {
  private var previousBrightness: CGFloat?
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
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(brightness: Double) {
    // Screen brightness must be raised BEFORE sampling starts and then held
    // flat. Ramping it mid-sequence would make our own UI a luminance shift
    // inside the baseline-vs-lit comparison — measuring ourselves, not the face.
    if previousBrightness == nil {
      previousBrightness = UIScreen.main.brightness
    }
    UIScreen.main.brightness = CGFloat(max(0.0, min(1.0, brightness)))

    lockCamera()
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
    if let previous = previousBrightness {
      UIScreen.main.brightness = previous
      previousBrightness = nil
    }

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
