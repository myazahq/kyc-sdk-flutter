import 'package:flutter/services.dart';

// ─── App screen brightness for the bright-screen liveness ────────────────────
//
// Raises THIS APP's screen brightness while the selfie camera is on, and puts
// it back afterwards. Never the system setting: on Android it is the activity
// window's own brightness (no WRITE_SETTINGS), on iOS UIScreen.main.brightness,
// saved and restored by the plugin. Rides the capture-tuning channel, which
// already owns the flash sequence's brightness; the native side counts both
// holders so neither restores the screen under the other.
//
// Best-effort throughout: a platform that refuses leaves the screen as it was,
// and nothing here throws into the flow. The theme change does not depend on it.

const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/capture_tuning');

/// Full brightness: the screen is the light on the face.
const double kBrightScreenLevel = 1.0;

/// Holds the screen raised, idempotently. [raise] twice is one raise; [restore]
/// without a raise is nothing. Safe to call from `dispose`.
class ScreenBrightnessBoost {
  ScreenBrightnessBoost({MethodChannel channel = _channel}) : _ch = channel;

  final MethodChannel _ch;
  bool _raised = false;

  /// Whether this boost currently holds the screen raised.
  bool get raised => _raised;

  Future<void> raise({double level = kBrightScreenLevel}) async {
    if (_raised) return;
    _raised = true;
    try {
      await _ch.invokeMethod<void>('setBrightness', {'brightness': level});
    } catch (_) {
      // Not implemented here, or the device refused: carry on unlit.
    }
  }

  Future<void> restore() async {
    if (!_raised) return;
    _raised = false;
    try {
      await _ch.invokeMethod<void>('restoreBrightness');
    } catch (_) {}
  }
}
