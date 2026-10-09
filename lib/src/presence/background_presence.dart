import 'dart:io' show Platform;

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

  /// A "still here" check-in from an inside reading the foreground reporter
  /// already took on app open. The native side records the running stay now
  /// rather than when the person leaves, so someone who hardly leaves home
  /// still earns background evidence. A no-op unless the background tier is
  /// armed; iOS confirms with its own region state. Never throws.
  static Future<void> checkIn({
    required double lat,
    required double lng,
    double? accuracy,
    required DateTime at,
    bool mocked = false,
  }) async {
    try {
      await _channel.invokeMethod<bool>('presenceCheckIn', {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        'timestamp': at.millisecondsSinceEpoch,
        'mocked': mocked,
      });
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

/// The two-step escalation to "allow all the time": while-in-use first, then
/// a second request for the background permission. Shared by the geofence and
/// the foreground-service tiers so the two can never ask differently. Null
/// when the platform could not answer at all.
Future<LocationPermission?> requestAlwaysLocationPermission() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      permission = await _requestAlwaysNatively(permission);
    }
    return permission;
  } catch (_) {
    return null;
  }
}

/// The second step is asked by the plugin's own native code on both
/// platforms, because geolocator's second request never reaches the system
/// prompt on either:
///   • iOS: it returns at once when any decision already exists, and with
///     both usage strings declared it only ever asks for "While Using".
///   • Android 11+: it asks for background location together with the
///     foreground permissions, and the system ignores a mixed request.
/// iOS shows its prompt once per install and Android stops after two
/// refusals; after that this answers the current permission without one.
Future<LocationPermission> _requestAlwaysNatively(LocationPermission current) async {
  if (!Platform.isIOS && !Platform.isAndroid) return current;
  try {
    final word = await const MethodChannel('kyc_sdk_flutter/presence')
        .invokeMethod<String>('requestAlwaysLocation');
    return alwaysAnswerToPermission(word, current);
  } catch (_) {
    return current;
  }
}

/// Pure: the native side's answer as a geolocator permission. An answer this
/// build does not know keeps [current].
LocationPermission alwaysAnswerToPermission(String? word, LocationPermission current) {
  switch (word) {
    case 'always':
      return LocationPermission.always;
    case 'whileInUse':
      return LocationPermission.whileInUse;
    case 'denied':
      return LocationPermission.deniedForever;
    default:
      return current;
  }
}
