import 'package:flutter/material.dart';

import '../config/regions.dart';
import '../config/theme.dart';
import 'country_option_tile.dart';
import 'myaza_input.dart';

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

  const CountryRegionPicker({
    super.key,
    required this.codes,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<CountryRegionPicker> createState() => _CountryRegionPickerState();
}

class _CountryRegionPickerState extends State<CountryRegionPicker> {
  String _query = '';

  bool _matches(CountryOption c, String q) =>
      c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final q = _query.trim().toLowerCase();

    final groups = <RegionGroup>[];
    for (final g in groupCountriesByRegion(widget.codes)) {
      final matched =
          q.isEmpty ? g.countries : g.countries.where((c) => _matches(c, q));
      if (matched.isNotEmpty) {
        groups.add(RegionGroup(g.region, matched.toList()));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyazaInput(
          hint: 'Search countries…',
          prefix: Icon(Icons.search, size: 18, color: colors.textSecondary),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: MyazaSpacing.md),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text('No countries match your search.',
                      style: text.bodyMedium),
                )
              : ListView(
                  // Content padding, not viewport padding: the list runs to the
                  // sheet's bottom edge (no dead safe-area band) while the last
                  // row can still scroll clear of the home indicator.
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom +
                        MyazaSpacing.md,
                  ),
                  children: [
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
