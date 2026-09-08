import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

// ─── The on-device pin store ─────────────────────────────────────────────────
//
// When a workflow enables presence verification, the captured pin is saved
// LOCALLY (keyed by the org's user reference) so later app opens can evaluate
// "am I at the address?" without the coordinates ever leaving the phone. A
// small JSON file in the app documents directory; every failure degrades to
// "no presence tier", never a crash. Mirrors the RN SDK's presence/store.ts.

const _kFileName = 'myaza-kyc-presence.json';

class StoredPin {
  final double lat;
  final double lng;
  final String savedAt;

  /// Whether this pin belongs to the always-on arrangement (never expires).
  final bool alwaysOn;
  const StoredPin({
    required this.lat,
    required this.lng,
    required this.savedAt,
    this.alwaysOn = false,
  });
}

Future<File?> _file() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_kFileName');
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> _readAll() async {
  final file = await _file();
  if (file == null) return {};
  try {
    if (!await file.exists()) return {};
    final parsed = jsonDecode(await file.readAsString());
    return parsed is Map<String, dynamic> ? parsed : {};
  } catch (_) {
    return {};
  }
}

Future<void> _writeAll(Map<String, dynamic> pins) async {
  final file = await _file();
  if (file == null) return;
  try {
    await file.writeAsString(jsonEncode(pins));
  } catch (_) {
    // Best-effort: a failed save costs the presence tier, never the flow.
  }
}

/// Saves the captured pin for later foreground reports. Never throws.
Future<void> savePresencePin(
  String externalUserId,
  double lat,
  double lng, {
  bool alwaysOn = false,
}) async {
  if (externalUserId.isEmpty) return;
  final pins = await _readAll();
  pins[externalUserId] = {
    'lat': lat,
    'lng': lng,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    if (alwaysOn) 'alwaysOn': true,
  };
  await _writeAll(pins);
}

/// How long a stored pin may drive reports. The watch it feeds resolves
/// within its policy window (30 days at the longest) and the server discards
/// reports for a resolved watch anyway, but the DEVICE kept sampling location
/// on every app open forever, for a check that had finished. The server
/// cannot say "stop" without breaking the ingest endpoint's enumeration
/// safety (an unknown user and a resolved watch must answer identically), so
/// the bound lives here: longest window plus resolution slack, then the pin
/// self-expires and the reporter goes quiet before ever touching the GPS.
/// Mirrors the RN store's PIN_TTL_DAYS; keep the two in lockstep.
const int kPinTtlDays = 45;

@visibleForTesting
bool pinExpiredAt(String savedAt, DateTime now) {
  // An unparseable stamp is treated as expired: this store has always written
  // savedAt, so a missing one is corruption, and corrupt entries must age out
  // rather than report forever.
  final saved = DateTime.tryParse(savedAt);
  if (saved == null) return true;
  // Strictly past the TTL, matching the RN mirror's millisecond comparison
  // (inDays truncates and would expire a pin hours early on one platform).
  return now.toUtc().difference(saved.toUtc()) > const Duration(days: kPinTtlDays);
}

/// The stored pin for a user, or null (no store / never captured here /
/// aged out — an expired pin is cleared on the way through).
Future<StoredPin?> loadPresencePin(String externalUserId) async {
  final raw = (await _readAll())[externalUserId];
  if (raw is! Map) return null;
  final lat = raw['lat'];
  final lng = raw['lng'];
  if (lat is! num || lng is! num) return null;
  // An always-on pin has no end date by design (the OkHi model): monitoring
  // continues until revoked, and the TTL exists only for BOUNDED watches
  // whose purpose has a deadline.
  final alwaysOn = raw['alwaysOn'] == true;
  if (!alwaysOn && pinExpiredAt((raw['savedAt'] as String?) ?? '', DateTime.now())) {
    await clearPresencePin(externalUserId);
    return null;
  }
  return StoredPin(
    lat: lat.toDouble(),
    lng: lng.toDouble(),
    savedAt: (raw['savedAt'] as String?) ?? '',
    alwaysOn: alwaysOn,
  );
}

/// Drops a stored pin (e.g. after a watch resolves or the user signs out).
Future<void> clearPresencePin(String externalUserId) async {
  final pins = await _readAll();
  if (pins.containsKey(externalUserId)) {
    pins.remove(externalUserId);
    await _writeAll(pins);
  }
}
