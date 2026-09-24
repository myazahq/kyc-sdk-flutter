import 'package:flutter/material.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/regions.dart';
import '../config/theme.dart';
import 'country_option_tile.dart';
import 'myaza_input.dart';
import 'icons/icons.dart';

// ─── Country region picker ────────────────────────────────────────────────────
//
// Searchable, region-grouped country list — used by the country-select step
// when a workflow offers more than 5 countries (below that it's a flat list).
// Mirrors the web SDK's CountryRegionPicker: a pinned search box over a
// scrollable list grouped by continent (Africa first, "Other" last, A→Z within).
//
// LAYOUT: the search box is pinned and the list takes ALL remaining height via
// [Expanded] — the web SDK's `flex-1 min-h-0`. That needs a bounded height,
// which the step body supplies through `KycBottomSheet.fillsViewport`. Don't
// render this inside a scroll view: the list would get an unbounded height and
// the Expanded would throw.

class CountryRegionPicker extends StatefulWidget {
  /// ISO-2 codes to offer.
  final List<String> codes;

  /// Currently selected code (highlighted), if any.
  final String? selected;

  /// Called with the picked ISO-2 code.
  final void Function(String code) onSelect;

  /// The visitor's IP country. Lifted out of its continent to the very top
  /// and tagged, so the one country most likely to be theirs is the first
  /// thing they see rather than something to scroll for.
  final String? geoCountry;

  const CountryRegionPicker({
    super.key,
    required this.codes,
    required this.selected,
    required this.onSelect,
    this.geoCountry,
  });

  @override
  State<CountryRegionPicker> createState() => _CountryRegionPickerState();
}

class _CountryRegionPickerState extends State<CountryRegionPicker> {
  String _query = '';

  bool _matches(String code, String q) =>
      countryLabel(code).toLowerCase().contains(q) ||
      code.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final q = _query.trim().toLowerCase();

    // Filter first, THEN pin: the geo row stays subject to the search, so
    // typing narrows to what was asked for rather than keeping a row that
    // does not match it.
    final visible = [
      for (final code in widget.codes)
        if (q.isEmpty || _matches(code, q)) code.toUpperCase(),
    ];
    final split = pinGeoRow(visible, widget.geoCountry, (c) => c);
    final pinned = split.pinned;
    final groups = groupCountriesByRegion(split.rest);
    final empty = groups.isEmpty && pinned == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyazaInput(
          hint: 'Search countries…',
          prefix: MyazaIcon(MyazaIcons.search, size: 18, color: colors.textSecondary),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: MyazaSpacing.md),
        Expanded(
          child: empty
              ? Center(
                  child: Text('No countries match your search.',
                      style: text.bodyMedium),
                )
              : ListView(
                  // The list runs to the PoweredBy footer, which owns the
                  // home-indicator clearance for the whole sheet — so only the
                  // visual gap is needed here.
                  padding: const EdgeInsets.only(bottom: MyazaSpacing.md),
                  children: [
                    if (pinned != null)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: MyazaSpacing.sm),
                        child: CountryOptionTile(
                          code: pinned,
                          label: countryLabel(pinned),
                          isSelected:
                              widget.selected?.toUpperCase() == pinned,
                          badge: 'Your location',
                          onTap: () => widget.onSelect(pinned),
                        ),
                      ),
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          MyazaSpacing.xs,
                          MyazaSpacing.sm,
                          MyazaSpacing.xs,
                          MyazaSpacing.sm,
                        ),
                        child: Text(
                          g.region.toUpperCase(),
                          style: text.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      for (final c in g.countries)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: MyazaSpacing.sm),
                          child: CountryOptionTile(
                            code: c.code,
                            label: c.name,
                            isSelected:
                                widget.selected?.toUpperCase() == c.code,
                            onTap: () => widget.onSelect(c.code),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
