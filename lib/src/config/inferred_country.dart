import 'dart:ui' show PlatformDispatcher;

// ─── Inferred country ─────────────────────────────────────────────────────────
//
// The visitor's most likely country, for DEFAULTS only (never evidence). A
// mirror of the web SDK's lib/inferred-country.ts and the RN SDK's — keep the
// three in lockstep.
//
// Two tiers: the server's IP-derived `geoCountry` when it exists, else the
// device locale's region (en_NG → NG). The second tier is what makes inference
// work where the IP cannot answer at all — a dev server on a loopback address,
// a carrier GeoLite2 cannot place — from a signal the device already carries.
// Both are guesses a person can correct; nothing recorded branches on them.

final RegExp _iso2 = RegExp(r'^[A-Z]{2}$');

/// [deviceCountry] overrides the platform locale's region (tests, hosts with
/// their own locale source).
String? inferredCountry(String? geoCountry, {String? deviceCountry}) {
  final geo = geoCountry?.trim().toUpperCase();
  if (geo != null && _iso2.hasMatch(geo)) return geo;
  final device =
      (deviceCountry ?? PlatformDispatcher.instance.locale.countryCode)
          ?.trim()
          .toUpperCase();
  return device != null && _iso2.hasMatch(device) ? device : null;
}
