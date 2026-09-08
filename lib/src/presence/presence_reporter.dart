import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/resolve_url.dart';
import 'presence_math.dart';
import 'presence_store.dart';
import 'presence_watch_wait.dart';

// ─── The FOREGROUND presence reporter — the default tier ─────────────────────
//
// The host app calls MyazaAddressPresence.report() on app open, or the moment
// the flow submits (presence_watch_wait.dart makes that safe: the watch is
// minted seconds after the submission is accepted, and a fresh pin waits for
// it); the SDK takes one while-in-use fix, evaluates the fence ON-DEVICE
// against the pin stored at capture, and posts a single per-day aggregate.
// Everything is best-effort: a denied permission, a missing pin, or a network
// fault returns a reason, never a throw — a presence report must never break
// the host app's startup path. Mirrors the RN SDK's presence/report.ts.

enum PresenceReportReason {
  reported,
  noPin,
  servicesOff,
  noFix,
  outsideFence,

  /// Nothing is monitoring this user right now, so a report would be dropped.
  noWatch,
  networkError,
}

class PresenceReportResult {
  final bool reported;

  /// Whether the fix landed inside the fence (null when nothing was evaluated).
  final bool? inside;
  final PresenceReportReason reason;
  const PresenceReportResult(this.reported, this.inside, this.reason);
}

class MyazaAddressPresence {
  MyazaAddressPresence._();

  /// A fix older than this no longer says where the phone is NOW.
  static const Duration _lastKnownMaxAge = Duration(minutes: 10);

  /// One fix, or null: a fresh read inside the window, else the platform's
  /// last known position when it is recent enough (RN's reporter learned the
  /// rungs the hard way on 2026-09-08: Expo's iOS read waits for a fix that
  /// meets the requested accuracy and never delivered one indoors; Geolocator
  /// returns the first update, but the fallback keeps the two reporters one
  /// rule).
  static Future<Position?> _oneShotFix() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        final known = await Geolocator.getLastKnownPosition();
        if (known != null &&
            DateTime.now().difference(known.timestamp) <= _lastKnownMaxAge) {
          return known;
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// One foreground presence report for [externalUserId] — the same user
  /// reference the KYC flow ran with. [apiKey] is the org's publishable key;
  /// [devUrl] overrides the server for development keys, exactly like the SDK
  /// config's field of the same name.
  static Future<PresenceReportResult> report({
    required String apiKey,
    required String externalUserId,
    String? devUrl,
  }) async {
    final pin = await loadPresencePin(externalUserId);
    if (pin == null) {
      return const PresenceReportResult(false, null, PresenceReportReason.noPin);
    }

    // The phone's location toggle, checked before the permission dance: off,
    // every fix fails, and `noFix` told the host nothing about why.
    bool services = true;
    try {
      services = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      // Unanswerable reads as on; the fix below still decides.
    }
    if (!services) {
      return const PresenceReportResult(false, null, PresenceReportReason.servicesOff);
    }

    final fix = await _oneShotFix();
    if (fix == null) {
      return const PresenceReportResult(false, null, PresenceReportReason.noFix);
    }

    final inside = insideFence(
      pinLat: pin.lat,
      pinLng: pin.lng,
      fixLat: fix.latitude,
      fixLng: fix.longitude,
      accuracy: fix.accuracy.isFinite && fix.accuracy > 0 ? fix.accuracy : null,
    );
    // An outside fix is NOT evidence of absence (people go to work) — the
    // server scores presence, never absence — so there is nothing worth
    // sending. A MOCKED fix is the exception: evidence OF fraud is worth more
    // to the watch than silence.
    if (!inside && !fix.isMocked) {
      return const PresenceReportResult(false, false, PresenceReportReason.outsideFence);
    }

    // The watch is minted seconds after a submission is accepted, and the
    // ingest drops a report that arrives before it (presence_watch_wait.dart).
    final watch = await awaitWatch(
      fresh: pinIsFresh(pin.savedAt),
      fetchStatus: () => fetchWatchStatus(apiKey, devUrl, externalUserId),
    );
    if (watch == WatchPresence.absent) {
      return PresenceReportResult(false, inside, PresenceReportReason.noWatch);
    }

    final local = localDayAndNight();
    try {
      final base = resolveBaseUrl(apiKey, devUrl: devUrl);
      final dio = Dio(BaseOptions(
        baseUrl: base,
        headers: {'Authorization': 'Bearer $apiKey'},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      await dio.post<Map<String, dynamic>>('/api/kyc/address/observations', data: {
        'externalUserId': externalUserId,
        'observations': [
          {
            'day': local.day,
            'source': 'foreground',
            'dwellMinutes': 0,
            'nightPresent': local.nightPresent,
            'samples': 1,
            if (fix.isMocked) 'integrity': {'mockLocation': true},
          },
        ],
      });
      return PresenceReportResult(true, inside, PresenceReportReason.reported);
    } catch (_) {
      return PresenceReportResult(false, inside, PresenceReportReason.networkError);
    }
  }
}
