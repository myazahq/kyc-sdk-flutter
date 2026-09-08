// ─── Declared-country adoption ───────────────────────────────────────────────
//
// ONE table decides when evidence about where the applicant IS may change the
// country they are DECLARING: a reverse-geocoded pin or current-location fix
// (a geocode), or the address they picked from search (explicit). It mirrors
// the web SDK's steps/address/country-adoption.ts and the RN SDK's
// lib/country-adoption.ts; the three run the shared vectors in
// test/country_adoption_vectors.json, so a drift in any one fails there.
//
// The rules, and why each exists:
//  - GEOCODED EVIDENCE outranks every GUESS. The address scope's default is
//    the IP country, and on a dev box that once declared US while the device
//    sat in Calabar (the search returned California), so the fix's own
//    geocode corrects a guess the moment it resolves.
//  - An EXPLICIT declaration is never overridden by a geocode; a PICKED
//    address replaces even that, since the pick is the applicant's newer and
//    more specific statement, and is then itself explicit.
//  - Outside the address scope `selectedCountry` is the ID-VERIFICATION
//    country, and changing it resets the ID choice, so only a guessed value
//    is ever corrected there, picked address or not.
//  - The org's accepted list (proofOfAddress.countries) gates every path: a
//    value the submission gate would refuse never becomes the declaration.

final RegExp _iso2 = RegExp(r'^[A-Z]{2}$');

/// A trimmed, upper-cased ISO-2, or null for anything that is not one.
String? normaliseIso2(String? raw) {
  final code = raw?.trim().toUpperCase();
  if (code == null || !_iso2.hasMatch(code)) return null;
  return code;
}

/// Whether the org's accepted-country list admits [code]. Null or empty
/// accepts everyone.
bool countryAccepted(List<String>? accepted, String code) {
  if (accepted == null || accepted.isEmpty) return true;
  return accepted.any((c) => c.trim().toUpperCase() == code);
}

/// What to do about a country the evidence named.
class CountryAdoption {
  /// The normalised ISO-2 to declare.
  final String country;

  /// Declare it as a GUESS (later evidence may correct it) rather than as the
  /// applicant's own explicit statement.
  final bool auto;
  const CountryAdoption(this.country, {required this.auto});
}

/// The adoption rule. See the file header for what each guard is for.
///
/// [scope] is the workflow scope (null = a full verification); [explicit]
/// says the country came from an address the applicant PICKED.
CountryAdoption? adoptionDecision({
  required String? country,
  required String? selectedCountry,
  required bool countryAutoPicked,
  required String? scope,
  required List<String>? accepted,
  bool explicit = false,
}) {
  final code = normaliseIso2(country);
  if (code == null) return null;
  final onAddressScope = scope == 'address';
  final guessed =
      countryAutoPicked || (onAddressScope && selectedCountry == null);
  if (!guessed && !(explicit && onAddressScope)) return null;
  if (code == normaliseIso2(selectedCountry)) return null;
  if (!countryAccepted(accepted, code)) return null;
  return CountryAdoption(code, auto: !explicit);
}

/// The address scope's default: the visitor's IP country, once, while nothing
/// is declared, and only when the accepted list admits it. A full flow never
/// defaults from the IP (there the country is the ID's).
String? geoDefaultCountry({
  required String? geoCountry,
  required String? selectedCountry,
  required String? scope,
  required List<String>? accepted,
}) {
  if (scope != 'address' || selectedCountry != null) return null;
  final code = normaliseIso2(geoCountry);
  if (code == null || !countryAccepted(accepted, code)) return null;
  return code;
}
