import 'dart:async';

import 'package:flutter/services.dart';

// ─── Capture tuning for flash liveness ────────────────────────────────────────
//
// Steadies the camera and the screen while a flash sequence runs, then puts
// both back. See CaptureTuning.swift for why each piece matters; in short, the
// camera's automatic white balance is designed to cancel exactly the colour
// cast the check measures, and the screen is the light source it measures by.
//
// Everything here is BEST-EFFORT. Tuning that fails leaves a weaker signal —
// more flashes scored inconclusive — never a failed verification. A user must
// not be blocked because their device wouldn't hold a white-balance lock.

const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/capture_tuning');

/// How long the screen and sensor need after the change before samples mean
/// anything. Brightness ramps are not instant and a locked exposure takes a
/// moment to settle; sampling through either would fold our own adjustment into
/// the baseline.
const Duration kTuningSettleDelay = Duration(milliseconds: 350);

/// Full brightness — the whole point is maximum emitted light.
const double kFlashBrightness = 1.0;

/// Locks the capture and raises the screen for a flash sequence.
///
/// Platform reach differs, deliberately:
///  • iOS — screen brightness AND white-balance/exposure lock, natively.
///  • Android — exposure lock only, via [lockExposure] (the camera plugin's
///    cross-platform API). Its white balance lives inside the camera plugin's
///    own Camera2 session, which a separate plugin cannot reach, and window
///    brightness needs an Activity this plugin doesn't hold. Both are follow-ups;
///    flash still works there, with a weaker signal in bright ambient light.
///
/// [lockExposure] is injected rather than imported so this stays free of the
/// camera provider (and testable without a camera).
Future<void> beginFlashTuning({
  Future<void> Function()? lockExposure,
  double brightness = kFlashBrightness,
}) async {
  try {
    await _channel.invokeMethod<void>('beginFlash', {'brightness': brightness});
  } catch (_) {
    // Not implemented on this platform, or the device refused — carry on.
  }
  if (lockExposure != null) {
    try {
      await lockExposure();
    } catch (_) {}
  }
  await Future<void>.delayed(kTuningSettleDelay);
}

/// Restores brightness and returns the camera to automatic.
///
/// Idempotent and never throws: call it from a `finally`. Leaving a user's
/// screen pinned at full brightness is a real cost they didn't agree to, so
/// this must run even when the sequence was abandoned or threw.
Future<void> endFlashTuning({Future<void> Function()? unlockExposure}) async {
  try {
    await _channel.invokeMethod<void>('restore');
  } catch (_) {}
  if (unlockExposure != null) {
    try {
      await unlockExposure();
    } catch (_) {}
  }
}
