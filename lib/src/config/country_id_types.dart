import 'kyc_config.dart';

// ─── Which ID types a country offers ──────────────────────────────────────────
//
// A workflow pins its ID selection PER COUNTRY, in `countries[].idTypes`. The
// top-level `idTypes` is the legacy single-country field and a consumer prop.
// Publish materialises the country list into the published config, so even a
// one-country flow arrives as a single-entry `countries` array with the
// selection inside it — a one-entry list is the normal shape, not a special
// case.
//
// Mirrors the web SDK's `KYCConfigContext` (`nonEmpty(countryEntry?.idTypes) ??
// nonEmpty(effective.idTypes)`) and the React Native `IdTypeStep`. Keep the
// three in lockstep.

/// The ID-type keys the flow pins for [country]: the matching `countries`
/// entry's own list, else the top-level `idTypes`.
///
/// Null means "every granted ID" — the server's own "unset = all" semantic. An
/// EMPTY per-country list means the same thing, so it falls through to the
/// top-level list rather than offering nothing.
List<String>? pinnedIdTypesFor(MyazaKYCConfig config, String country) {
  final countries = config.countries;
  if (countries != null) {
    for (final option in countries) {
      if (option.country.toUpperCase() != country.toUpperCase()) continue;
      final pinned = option.idTypes;
      if (pinned != null && pinned.isNotEmpty) return pinned;
      break;
    }
  }
  final top = config.idTypes;
  return (top != null && top.isNotEmpty) ? top : null;
}
