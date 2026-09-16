import AVFoundation
import Flutter

/// Reports the app's camera authorization straight from AVFoundation.
///
/// The SDK previously read this through `permission_handler`, which on iOS
/// compiles each permission strategy behind a macro:
///
///     #ifndef PERMISSION_CAMERA
///         #define PERMISSION_CAMERA 0
///     #endif
///
/// Unless the HOST app adds `PERMISSION_CAMERA=1` to its Podfile, the camera
/// strategy is compiled out and the status is reported as denied forever — even
/// with access fully granted. The visible symptom was the "allow camera access"
/// primer appearing on every capture step no matter how many times the user had
/// already allowed it.
///
/// An SDK cannot depend on consumers patching their Podfile for a core screen to
/// behave, so the check is asked of the system directly. This is also the same
/// authorization the `camera` plugin itself acts on, so the pre-check and the
/// actual camera open can no longer disagree.
///
/// Read-only by design: it never triggers the OS prompt. Requesting stays with
/// the camera controller, so the prompt appears at the moment the preview opens
/// rather than from a background status query.
public class CameraPermission: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/camera_permission",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(CameraPermission(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(Self.statusName())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Mapped to stable strings rather than raw enum ints so a future AVFoundation
  /// case can't silently shift meaning on the Dart side.
  private static func statusName() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return "granted"
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "denied"
    }
  }
}
