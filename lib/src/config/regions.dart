import 'country_names.g.dart';
import 'id_types.dart' show countryLabel;

// ─── Region grouping ──────────────────────────────────────────────────────────
//
// Groups ISO-2 country codes into continents for the searchable country-select
// picker (used once a workflow offers more than ~5 countries). A direct port of
// the web SDK's lib/regions.ts `groupCountriesByRegion`: Africa first, "Other"
// last, names A→Z within each region. Region membership + names come from the
// generated `country_names.g.dart` (kRegionByCode + kCountryNames).

const List<String> kRegionOrder = [
  'Africa',
  'Europe',
  'Americas',
  'Middle East',
  'Asia & Pacific',
  'Other',
];

/// One country in the picker: its ISO-2 code + display name.
class CountryOption {
  final String code;
  final String name;
  const CountryOption(this.code, this.name);
}

/// A region header + its countries (already sorted A→Z).
class RegionGroup {
  final String region;
  final List<CountryOption> countries;
  const RegionGroup(this.region, this.countries);
}

/// Groups [codes] by region (Africa first, "Other" last), names A→Z within.
List<RegionGroup> groupCountriesByRegion(List<String> codes) {
  final buckets = <String, List<CountryOption>>{};
  for (final raw in codes) {
    final code = raw.toUpperCase();
    final region = kRegionByCode[code] ?? 'Other';
    (buckets[region] ??= []).add(CountryOption(code, countryLabel(code)));
  }
  final groups = <RegionGroup>[];
  for (final region in kRegionOrder) {
    final list = buckets[region];
    if (list == null) continue;
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    groups.add(RegionGroup(region, list));
  }
  return groups;
}
