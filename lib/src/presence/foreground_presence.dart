import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/resolve_url.dart';
import 'background_presence.dart';
import 'presence_store.dart';

// ─── The Android FOREGROUND SERVICE tier — the OkHi reliability move ─────────
//
// A geofence alone is not reliable on Android 8+ once a manufacturer's
// battery manager decides an app is idle: transitions are dropped and nothing
// says so, the watch quietly lapses to inconclusive, and the phones on that
// list (Tecno, Infinix, itel, Xiaomi, Oppo, Vivo) are the ones our markets
// carry. A foreground service, with its persistent notification, is the one
// thing those managers leave alone.
//
// The plugin's PresenceForegroundService keeps the process alive, takes a
// low-power fix every few minutes, and turns those positions into the same
// enter/exit spans the geofence tier folds (PresenceSampler.kt, on the SAME
// stored enterAt, so the two cooperate rather than double-count). It also
// re-arms the fence whenever the phone's location toggle comes back on, and
// flushes a queue an offline EXIT left behind.
//
// Android only, opt-in, and the notification is the HOST's to word: its title
// and body reach the person's status bar. The host must also DECLARE the
// service and its two permissions in its own manifest (see the README), for
// the same reason it declares background location itself: a location
// foreground service changes the app's Play review posture, and that decision
// belongs to the host, made knowingly. On iOS region monitoring is reliable
// on its own, so enable() answers unsupportedPlatform there.
// Mirrors the RN SDK's presence/foreground-service.ts.

/// The persistent notification's content. The title and body are shown to
/// the person for as long as the service runs; the channel gets its own id
/// so the host's existing channels are never touched.
class PresenceNotification {
  /// e.g. "Address verification in progress"
  final String title;

  /// e.g. "Check the app to see your progress"
  final String body;
  final String channelId;
  final String channelName;
  final String? channelDescription;

  /// ARGB colour for the notification accent (e.g. `0xFF5645F5`).
  final int? color;

  const PresenceNotification({
    required this.title,
    required this.body,
    this.channelId = 'myaza_kyc_presence',
    this.channelName = 'Address verification',
    this.channelDescription,
    this.color,
  });

  Map<String, Object?> toMap() => {
        'title': title,
        'body': body,
        'channelId': channelId,
        'channelName': channelName,
        'channelDescription': channelDescription,
        'color': color,
      };
}

enum ForegroundServiceReason {
  started,
  unsupportedPlatform,
  noPin,
  permissionDenied,
  backgroundDenied,

  /// The host's manifest does not declare the service or its permissions.
  notDeclared,
  unavailable,
}

class EnableForegroundServiceResult {
  final bool started;
  final ForegroundServiceReason reason;
  const EnableForegroundServiceResult(this.started, this.reason);
}

class MyazaPresenceService {
  MyazaPresenceService._();

  static const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/presence');

  /// Starts the service on [externalUserId]'s stored pin. Asks for the
  /// location permissions on the way (while-in-use, then always) and arms
  /// the geofence too, so a host that calls only this still gets the fence.
  /// Never throws; every refusal comes back as a reason.
  static Future<EnableForegroundServiceResult> enable({
    required String apiKey,
    required String externalUserId,
    required PresenceNotification notification,
    String? devUrl,
  }) async {
    if (!Platform.isAndroid) {
      return const EnableForegroundServiceResult(
          false, ForegroundServiceReason.unsupportedPlatform);
    }
    final pin = await loadPresencePin(externalUserId);
    if (pin == null) {
      return const EnableForegroundServiceResult(false, ForegroundServiceReason.noPin);
    }
    final permission = await requestAlwaysLocationPermission();
    if (permission == null) {
      return const EnableForegroundServiceResult(false, ForegroundServiceReason.unavailable);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const EnableForegroundServiceResult(
          false, ForegroundServiceReason.permissionDenied);
    }
    if (permission != LocationPermission.always) {
      return const EnableForegroundServiceResult(
          false, ForegroundServiceReason.backgroundDenied);
    }
    try {
      final base = resolveBaseUrl(apiKey, devUrl: devUrl);
      final outcome = await _channel.invokeMethod<String>('enablePresenceService', {
        'lat': pin.lat,
        'lng': pin.lng,
        'radius': kGeofenceRadiusMeters,
        'baseUrl': base,
        'apiKey': apiKey,
        'externalUserId': externalUserId,
        'notification': notification.toMap(),
      });
      switch (outcome) {
        case 'started':
          return const EnableForegroundServiceResult(true, ForegroundServiceReason.started);
        case 'not_declared':
          return const EnableForegroundServiceResult(
              false, ForegroundServiceReason.notDeclared);
        default:
          return const EnableForegroundServiceResult(
              false, ForegroundServiceReason.unavailable);
      }
    } catch (_) {
      // MissingPluginException included: a host without the native side
      // simply has no service tier.
      return const EnableForegroundServiceResult(false, ForegroundServiceReason.unavailable);
    }
  }

  /// Stops the service and its notification. The geofence stays armed.
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disablePresenceService');
    } catch (_) {
      // Best-effort by contract.
    }
  }

  /// Whether the service is running right now (always false on iOS).
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isPresenceServiceRunning') == true;
    } catch (_) {
      return false;
    }
  }
}
