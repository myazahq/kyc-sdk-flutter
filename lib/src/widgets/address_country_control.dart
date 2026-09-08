import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/country_names.g.dart' show kCountryNames;
import '../config/id_types.dart' show countryLabel;
import '../config/inferred_country.dart';
import '../config/scope.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import 'country_field.dart';
import 'country_flag.dart';

// ─── Address-scope country control ───────────────────────────────────────────
//
// The declared-country control for ADDRESS-SCOPED flows — mounted on the Proof
// of Address screen (the Didit PoA model: the applicant names their market,
// then uploads the document). Mirrors the web SDK's
// steps/address/AddressCountryControl and the RN twin: the pick drives the
// document kinds on offer, the search filter, the map's opening view, the PoA
// vendor market, and rides the submission as the verification's country. The
// pin stays the ground truth regardless.
//
// The picker is the house country sheet (CountryField) in its region-grouped
// mode, with the inferred country (server geo first, device locale second)
// pinned on top as "Your location" — the web's region menu, in the sheet the
// rest of the mobile flow uses (user decision 2026-09-06).

/// What the picker offers: the org's accepted list (unknown codes dropped),
/// else every named country.
List<String> poaOfferedCountries(List<String> configured) {
  final list = configured
      .map((c) => c.toUpperCase())
      .where(kCountryNames.containsKey)
      .toList(growable: false);
  return list.isNotEmpty ? list : kCountryNames.keys.toList(growable: false);
}

class AddressCountryControl extends ConsumerWidget {
  const AddressCountryControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(kycConfigProvider);
    if (configScope(config.scope) != 'address') return const SizedBox.shrink();

    final state = ref.watch(kYCNotifierProvider);
    final colors = context.myazaColors;
    final text = context.myazaText;
    final offered =
        poaOfferedCountries(config.proofOfAddress?.countries ?? const []);
    // Only a country the applicant PICKED shows as selected: the address
    // scope has no seeded country to show (web's AddressCountryControl, the
    // same rule), and showing config.country here while the attachment
    // area's flag read `selectedCountry` had the two disagreeing.
    final value = state.selectedCountry ?? '';
    void pick(String code) =>
        ref.read(kYCNotifierProvider.notifier).setCountry(code);

    // One accepted country = nothing to pick. Show it as a settled fact rather
    // than a sheet that could only ever re-answer itself.
    // The label sits ABOVE the field, as it does on every other input (user
    // decision 2026-09-05) — the read-only box is CountryField's trigger
    // without the chevron, so the settled and pickable states line up.
    if (offered.length == 1) {
      final only = offered.single;
      return Padding(
        padding: const EdgeInsets.only(bottom: MyazaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Country', style: text.label),
            const SizedBox(height: MyazaSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyazaSpacing.md,
                vertical: MyazaSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MyazaRadius.sm),
                border: Border.all(color: colors.border),
                color: colors.backgroundSecondary,
              ),
              child: Row(
                children: [
                  MyazaCountryFlag(country: only, size: 20),
                  const SizedBox(width: MyazaSpacing.sm),
                  Expanded(
                    child: Text(
                      countryLabel(only),
                      style: text.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: MyazaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Country', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          CountryField(
            country: value,
            codes: offered,
            onChanged: pick,
            placeholder: 'Select country',
            // The inferred country pinned on top of the sheet; the sheet
            // itself drops it when the org's list does not carry it.
            geoCountry: inferredCountry(state.serverConfig.geoCountry),
            grouped: true,
          ),
        ],
      ),
    );
  }
}
