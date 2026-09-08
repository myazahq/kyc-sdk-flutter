import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_failure.dart';

export 'attest_fix.dart';
export 'location_failure.dart';

// ─── One-shot geolocation for the address-collection step ────────────────────
//
// Best-effort BY CONTRACT, mirroring the web SDK's address helpers and the RN
// SDK's services/location.ts: a denied permission, a device with location off,
// or a slow fix costs the `attested` tier (or the recentre convenience) —
// never the flow. The attest fix resolves to null / {} on any failure; the
// PIN's fix says WHY it failed, so the copy can send the person to the right
// remedy (location_failure.dart).

const Duration _kFixTimeout = Duration(seconds: 8);

/// Accuracy at which a fix is good enough to stop waiting for GPS.
const double kPreciseEnoughM = 25;

/// Hard ceiling on the whole precise-fix watch.
const Duration kPreciseWindow = Duration(seconds: 8);

/// Once ANY fix exists, wait only this much longer for a better one. A wifi or
/// cell fix never reaches 25m, and waiting out the whole window for an accuracy
/// that is not coming reads as "keeps loading".
const Duration kFirstFixGrace = Duration(seconds: 3);

/// The canned preview pin (Lagos), used in place of the hardware so a preview
/// never asks for a location permission it has no business wanting.
const double kPreviewFixLat = 6.4281;
const double kPreviewFixLng = 3.4219;
const double kPreviewFixAccuracy = 15;

class DeviceFix {
  final double lat;
  final double lng;
  final double? accuracy;
  final DateTime timestamp;

  /// The platform's own mock-location flag; null when it cannot say.
  final bool? mocked;
  const DeviceFix({
    required this.lat,
    required this.lng,
    this.accuracy,
    required this.timestamp,
    this.mocked,
  });
}

// The most recent fix ANY read produced, kept so the confirm-time attest read
// can fall back on it (see pickDeviceFix / deviceFixFor).
DeviceFix? _lastGoodFix;
DeviceFix _remember(DeviceFix fix) {
  _lastGoodFix = fix;
  return fix;
}

/// The most recent fix any read produced this session, for the attest step.
DeviceFix? lastGoodFix() => _lastGoodFix;

/// How old a fix from earlier in the SAME address flow may be and still stand
/// in for the confirm-time read. Placing a pin takes a minute or two; a fix
/// from that window still says the device was here, and the server judges it
/// by its own `capturedAt` anyway.
const Duration kRecentFixMaxAge = Duration(minutes: 3);

/// The reading the attest step should send: a fresh one when the read
/// answered, else the recent one the flow already took, else nothing. Pure, so
/// the rule is testable without a GPS. Mirrors RN's pickDeviceFix.
DeviceFix? pickDeviceFix(DeviceFix? fresh, DeviceFix? recent, {DateTime? now}) {
  if (fresh != null) return fresh;
  if (recent == null || recent.mocked == true) return null;
  final age = (now ?? DateTime.now()).difference(recent.timestamp);
  return age <= kRecentFixMaxAge ? recent : null;
}

/// A GPS read: the fix, or WHY there is none. Mirrors the RN SDK's
/// PreciseFixOutcome.
class DeviceFixResult {
  final DeviceFix? fix;
  final LocationFailure? failure;
  const DeviceFixResult.ok(DeviceFix this.fix) : failure = null;
  const DeviceFixResult.failed(LocationFailure this.failure) : fix = null;
}

/// One GPS fix, or null. Asks for foreground ("while in use") permission on
/// first use — the host app must carry the platform permission strings (see
/// the README's Address Intelligence section) or iOS crashes on the request.
///
/// This is the ATTEST fix, taken at confirm: one read, a cached one accepted,
/// because it answers "was the applicant here when they confirmed?" rather than
/// placing the pin. [precisePosition] is the pin's fix and is stricter.
Future<DeviceFix?> currentPosition() async {
  try {
    if (!await _ensurePermission()) return null;
    final fix = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: _kFixTimeout,
      ),
    );
    return _remember(DeviceFix(
      lat: fix.latitude,
      lng: fix.longitude,
      accuracy: fix.accuracy.isFinite && fix.accuracy > 0 ? fix.accuracy : null,
      timestamp: fix.timestamp,
      mocked: fix.isMocked,
    ));
  } catch (_) {
    return null;
  }
}

/// Whether foreground location is usable, asking for it once if it has never
/// been answered. Returns false rather than throwing on any refusal.
Future<bool> _ensurePermission() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission != LocationPermission.denied &&
      permission != LocationPermission.deniedForever;
}

/// A PRECISE fix: watch the position for up to [kPreciseWindow] and keep the
/// most accurate reading, resolving early once it is within [kPreciseEnoughM].
///
/// A single one-shot read is NOT acceptable for placing a pin: it routinely
/// answers with the first coarse wifi or cell fix, hundreds of metres out,
/// which is exactly the pin landing on the wrong compound. Nothing cached is
/// accepted either, for the same reason.
///
/// Never throws: every failure is CLASSIFIED, and every caller falls back to
/// placing the pin by hand.
Future<DeviceFixResult> precisePositionResult() async {
  bool granted;
  try {
    granted = await _ensurePermission();
  } catch (_) {
    // No location plugin behind the call: nothing on this device can answer.
    return const DeviceFixResult.failed(LocationFailure.unsupported);
  }
  if (!granted) return const DeviceFixResult.failed(LocationFailure.denied);
  try {
    // Permission granted with the toggle OFF is the failure people hit most,
    // and it is the one "allow location access" sends them the wrong way on.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DeviceFixResult.failed(LocationFailure.unavailable);
    }
  } catch (_) {
    // Let the watch decide.
  }
  try {
    final completer = Completer<Position?>();
    Position? best;
    Timer? grace;
    Timer? window;
    StreamSubscription<Position>? sub;
    var streamFailed = false;

    void finish(Position? fix) {
      if (completer.isCompleted) return;
      grace?.cancel();
      window?.cancel();
      unawaited(sub?.cancel());
      completer.complete(fix);
    }

    window = Timer(kPreciseWindow, () => finish(best));
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    ).listen(
      (fix) {
        if (best == null || fix.accuracy < best!.accuracy) best = fix;
        if (fix.accuracy > 0 && fix.accuracy <= kPreciseEnoughM) {
          finish(fix);
          return;
        }
        // First usable reading: give the GPS a short grace to improve, then
        // take the best on hand rather than waiting out the whole window.
        grace ??= Timer(kFirstFixGrace, () => finish(best));
      },
      onError: (_) {
        streamFailed = true;
        finish(best);
      },
      cancelOnError: false,
    );

    final fix = await completer.future;
    if (fix == null) {
      return DeviceFixResult.failed(
        streamFailed ? LocationFailure.unavailable : LocationFailure.timeout,
      );
    }
    return DeviceFixResult.ok(_remember(DeviceFix(
      lat: fix.latitude,
      lng: fix.longitude,
      accuracy: fix.accuracy.isFinite && fix.accuracy > 0 ? fix.accuracy : null,
      timestamp: fix.timestamp,
      mocked: fix.isMocked,
    )));
  } catch (_) {
    return const DeviceFixResult.failed(LocationFailure.unavailable);
  }
}

/// The Use-my-location fix: a canned pin in preview, the precise
/// best-of-watch fix otherwise, with the reason when there is none.
Future<DeviceFixResult> resolveMyLocation({bool preview = false}) async {
  if (preview) {
    return DeviceFixResult.ok(DeviceFix(
      lat: kPreviewFixLat,
      lng: kPreviewFixLng,
      accuracy: kPreviewFixAccuracy,
      timestamp: DateTime.now(),
    ));
  }
  return precisePositionResult();
}
