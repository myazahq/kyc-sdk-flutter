import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/resolve_url.dart';
import 'presence_store.dart';

// ─── The BACKGROUND presence tier — native geofencing ────────────────────────
//
// The OS wakes the app on fence crossings around the stored pin: entries stamp
// a timestamp, exits fold the dwell span into per-day aggregates and flush
// them, all natively so it works with the app killed. Only derived day records
// ever leave the phone, the same privacy floor as the foreground tier.
//
// Permissions are requested HERE in Dart (geolocator's documented two-step:
// while-in-use first, then the escalation to "always"); the native side never
// prompts. The host must declare the background-location entries itself
// (Android manifest + iOS Info.plist), because that declaration changes an
// app's store review posture and the decision belongs to the host, made
// knowingly. Mirrors the RN SDK's presence/background.ts.

/// The fence radius, in metres. The server credits a fix as at-address within
/// max(250, accuracy, capped 1km) — see kyc-core address-intel/presence — and
/// the RN tier registers the same 250. Keep the three in lockstep.
const int kGeofenceRadiusMeters = 250;

enum BackgroundPresenceReason {
  started,
  noPin,
  permissionDenied,
  backgroundDenied,
  unavailable,
}

class EnableBackgroundResult {
  final bool started;
  final BackgroundPresenceReason reason;
  const EnableBackgroundResult(this.started, this.reason);
}

class MyazaBackgroundPresence {
  MyazaBackgroundPresence._();

  static const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/presence');

  /// Arms the native geofence for [externalUserId]'s stored pin. Asks for the
  /// location permissions on the way (while-in-use, then always). Never
  /// throws; every refusal comes back as a reason.
  static Future<EnableBackgroundResult> enable({
    required String apiKey,
    required String externalUserId,
    String? devUrl,
  }) async {
    final pin = await loadPresencePin(externalUserId);
    if (pin == null) {
      return const EnableBackgroundResult(false, BackgroundPresenceReason.noPin);
    }
    final permission = await requestAlwaysLocationPermission();
    if (permission == null) {
      return const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const EnableBackgroundResult(
          false, BackgroundPresenceReason.permissionDenied);
    }
    if (permission != LocationPermission.always) {
      return const EnableBackgroundResult(false, BackgroundPresenceReason.backgroundDenied);
    }
    try {
      final base = resolveBaseUrl(apiKey, devUrl: devUrl);
      final ok = await _channel.invokeMethod<bool>('enablePresence', {
        'lat': pin.lat,
        'lng': pin.lng,
        'radius': kGeofenceRadiusMeters,
        'baseUrl': base,
        'apiKey': apiKey,
        'externalUserId': externalUserId,
      });
      return ok == true
          ? const EnableBackgroundResult(true, BackgroundPresenceReason.started)
          : const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    } catch (_) {
      // MissingPluginException included: a host without the native side
      // simply has no background tier.
      return const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    }
  }

  /// Removes the native geofence and clears the stored reporter config.
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disablePresence');
    } catch (_) {
      // Best-effort by contract.
    }
  }

  /// Whether the native geofence is registered right now.
  static Future<bool> isArmed() async {
    try {
      return await _channel.invokeMethod<bool>('isPresenceArmed') == true;
    } catch (_) {
      return false;
    }
  }
}

/// The documented two-step escalation to "allow all the time": while-in-use
/// first, then a second request that (with the background entries declared
/// by the host) raises the always prompt. Shared by the geofence and the
/// foreground-service tiers so the two can never ask differently. Null when
/// the platform could not answer at all.
Future<LocationPermission?> requestAlwaysLocationPermission() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  } catch (_) {
    return null;
  }
}
