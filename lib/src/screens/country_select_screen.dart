import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/country_option_tile.dart';
import '../widgets/country_region_picker.dart';

// ─── Country select screen ────────────────────────────────────────────────────
//
// Shown when a workflow offers more than one country. ≤5 countries render as a
// flat tappable list; above that a searchable region-grouped picker
// (SEARCH_THRESHOLD = 5, matching the web SDK). Picking a country sets it as the
// effective country and advances — the ID list then reflects that country.

const int _kSearchThreshold = 5;

class CountrySelectScreen extends ConsumerWidget {
  const CountrySelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(kycConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final options = config.countries ?? const [];
    final selected = state.selectedCountry;

    void pick(String code) {
      notifier.setCountry(code);
      notifier.nextStep();
    }

    if (options.length > _kSearchThreshold) {
      return CountryRegionPicker(
        codes: [for (final o in options) o.country],
        selected: selected,
        onSelect: pick,
      );
    }

    // The step body is in fill mode (see KycBottomSheet.fillsViewport), so this
    // short list owns its scroll too — keeps it safe on small screens.
    return ListView(
      // Same content-padding rule as the searchable picker: the list reaches
      // the sheet's bottom edge, the inset rides with the content.
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + MyazaSpacing.md,
      ),
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
            child: CountryOptionTile(
              code: o.country,
              label: countryLabel(o.country),
              isSelected: selected?.toUpperCase() == o.country.toUpperCase(),
              onTap: () => pick(o.country),
            ),
          ),
      ],
    );
  }
}
