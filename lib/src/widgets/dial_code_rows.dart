import '../config/regions.dart' show groupCountriesByRegion, pinGeoRow;

// ─── What the country sheet lists, as data ───────────────────────────────────
//
// Extracted from dial_code_picker.dart (200-line rule) so the ListView only
// renders: the pinned geo row and the optional REGION grouping decide here,
// and a unit test reads the result without pumping a sheet. Grouping is what
// the address-scope country control asks for (user decision 2026-09-06): its
// sheet reads like the web's region menu and the country-select step — a
// continent header, then its countries A–Z — rather than one 240-row
// alphabet. Mirrors the RN SDK's dialCodeRows.ts.

/// One country in the sheet: ISO-2, display name, and the dialling code
/// without its '+' (empty on the plain country picker).
typedef DialCodeEntry = ({String iso, String name, String dial});

sealed class DialCodeItem {
  const DialCodeItem();
}

/// A country row; [pinned] marks the visitor's own ("Your location").
final class DialCodeRowItem extends DialCodeItem {
  final DialCodeEntry entry;
  final bool pinned;
  const DialCodeRowItem(this.entry, {this.pinned = false});
}

/// A region label above the rows that follow it.
final class DialCodeHeaderItem extends DialCodeItem {
  final String region;
  const DialCodeHeaderItem(this.region);
}

/// The sheet's items over the ALREADY-FILTERED entries: where they appear to
/// be first (lifted out of the alphabet, still subject to the search), then
/// the rest — flat in the given order, or under region headers when [grouped].
List<DialCodeItem> buildDialCodeItems(
  List<DialCodeEntry> visible,
  String? geoCountry, {
  required bool grouped,
}) {
  final split = pinGeoRow(visible, geoCountry, (e) => e.iso);
  final geo = split.pinned;
  final items = <DialCodeItem>[
    if (geo != null) DialCodeRowItem(geo, pinned: true),
  ];
  if (!grouped) {
    items.addAll([for (final e in split.rest) DialCodeRowItem(e)]);
    return items;
  }
  final byIso = {for (final e in split.rest) e.iso.toUpperCase(): e};
  final groups = groupCountriesByRegion([for (final e in split.rest) e.iso]);
  for (final group in groups) {
    items.add(DialCodeHeaderItem(group.region));
    for (final c in group.countries) {
      final entry = byIso[c.code];
      if (entry != null) items.add(DialCodeRowItem(entry));
    }
  }
  return items;
}
