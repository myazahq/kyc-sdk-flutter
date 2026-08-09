import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart' show countrySelectOptions;
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
    // Multi-region flows carry `countries`; the KYB applicant leg does not,
    // so it offers the org's GRANTED countries — see countrySelectOptions.
    final codes = countrySelectOptions(config, state);
    final selected = state.selectedCountry;

    void pick(String code) {
      notifier.setCountry(code);
      notifier.nextStep();
    }

    if (codes.length > _kSearchThreshold) {
      return CountryRegionPicker(
        codes: codes,
        selected: selected,
        onSelect: pick,
      );
    }

    // The step body is in fill mode (see KycBottomSheet.fillsViewport), so this
    // short list owns its scroll too — keeps it safe on small screens.
    return ListView(
      // The list runs to the PoweredBy footer, which owns the home-indicator
      // clearance for the whole sheet — so only the visual gap is needed here.
      padding: const EdgeInsets.only(bottom: MyazaSpacing.md),
      children: [
        for (final code in codes)
          Padding(
            padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
            child: CountryOptionTile(
              code: code,
              label: countryLabel(code),
              isSelected: selected?.toUpperCase() == code.toUpperCase(),
              onTap: () => pick(code),
            ),
          ),
      ],
    );
  }
}
