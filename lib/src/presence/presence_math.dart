import 'dart:math' as math;

// ─── Presence math — the pure half of the foreground reporter ────────────────
//
// On-device evaluation is the contract: the phone decides "inside the fence?"
// and "what local day/night is it?", and only the derived record (day + flag)
// ever leaves the device. Raw coordinates never travel after capture.
//
// Mirrors the RN SDK's presence/math.ts — keep the two in lockstep.

const double _kEarthRadiusM = 6371000;

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _kEarthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

/// The server's at-address rule, applied on-device: 250 m, widened to the
/// fix's reported accuracy, capped at 1 km.
bool insideFence({
  required double pinLat,
  required double pinLng,
  required double fixLat,
  required double fixLng,
  double? accuracy,
}) {
  final radius = math.min(1000.0, math.max(250.0, accuracy ?? 0));
  return haversineMeters(pinLat, pinLng, fixLat, fixLng) <= radius;
}

/// The observation's day + night flag from the DEVICE's local clock — that is
/// the whole point of on-device evaluation. Night = 20:00–05:59 local.
({String day, bool nightPresent}) localDayAndNight([DateTime? at]) {
  final now = at ?? DateTime.now();
  String pad(int n) => n.toString().padLeft(2, '0');
  return (
    day: '${now.year}-${pad(now.month)}-${pad(now.day)}',
    nightPresent: now.hour >= 20 || now.hour < 6,
  );
}
