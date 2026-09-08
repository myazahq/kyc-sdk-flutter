import '../config/address_collection.dart';
import 'location_service.dart';

// ─── The attest-presence device fix ──────────────────────────────────────────
//
// Taken at CONFIRM, one read, a cached one accepted: it answers "was the
// applicant here when they confirmed?" rather than placing the pin. Split from
// location_service.dart (200-line rule); re-exported from there so callers
// keep one import.

/// The fix as the fields the verify body carries. Empty when no fix could be
/// taken — the submission simply goes without the `attested` tier.
Future<Map<String, dynamic>> deviceFixFields() async {
  final fix = // A single read at confirm routinely times out on iOS while the GPS
  // settles, and the submission then went out with no fix even though
  // "Use my location" had just placed the pin on one (2026-09-07). The
  // fix the flow already holds is the fallback (mirrors RN).
  pickDeviceFix(await currentPosition(), lastGoodFix());
  if (fix == null) return const {};
  return {
    'deviceLat': fix.lat,
    'deviceLng': fix.lng,
    if (fix.accuracy != null) 'deviceAccuracy': fix.accuracy,
    'capturedAt': fix.timestamp.toUtc().toIso8601String(),
  };
}

/// The one-shot attest fix applied onto the collected address — best-effort:
/// a denied or slow read returns the state untouched (it costs the `attested`
/// tier, never the flow).
Future<AddressState> withDeviceFix(AddressState current) async {
  final fix = await deviceFixFields();
  if (fix.isEmpty) return current;
  return current.copyWith(
    deviceLat: (fix['deviceLat'] as num?)?.toDouble(),
    deviceLng: (fix['deviceLng'] as num?)?.toDouble(),
    deviceAccuracy: (fix['deviceAccuracy'] as num?)?.toDouble(),
    capturedAt: fix['capturedAt'] as String?,
  );
}
