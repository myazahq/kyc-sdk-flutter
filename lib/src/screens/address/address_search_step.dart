import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/map_tiles.dart' show MapLatLng;
import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';
import 'address_flow_scaffold.dart';
import 'address_location_row.dart';
import 'address_pin_move.dart';
import 'address_search_body.dart';

/// Step 1 of the address flow: find the address as words.
///
/// Every path — a picked candidate, the current location, or "place a pin
/// instead" — lands on the pin step. Mirrors the web and RN SDKs'
/// AddressSearchStep; keep the copy in lockstep.
class AddressSearchStep extends ConsumerStatefulWidget {
  const AddressSearchStep({super.key});

  @override
  ConsumerState<AddressSearchStep> createState() => _AddressSearchStepState();
}

class _AddressSearchStepState extends ConsumerState<AddressSearchStep>
    with AddressFlowScaffold<AddressSearchStep> {
  @override
  KYCStep get step => KYCStep.addressSearch;

  @override
  void initState() {
    super.initState();
    // Warm the GPS and its reverse geocode from the moment the flow is
    // reached, UNDER the primer too: by the time "Got it" is tapped the fix is
    // usually already resolved, so the location row carries the address
    // immediately and the pin lands with no hesitation.
    WidgetsBinding.instance.addPostFrameCallback((_) => flow.startPrefetch());
  }

  void _toPin() =>
      ref.read(kYCNotifierProvider.notifier).goToStep(KYCStep.addressCollection);

  @override
  Widget buildBody(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AddressSearchBody(
            api: flow.api,
            autocomplete:
                flow.state.serverConfig.addressSearchMode == 'autocomplete',
            country: flow.country,
            near: flow.fix == null
                ? null
                : MapLatLng(flow.fix!.lat, flow.fix!.lng),
            onResolved: (place) {
              // The picked address's own country IS the declaration (a pick
              // is the applicant saying "this is my address"), under the same
              // guess-only / accepted-list rules as every geocode adoption.
              flow.adoptGeocodedCountry(place.country, explicit: true);
              flow.writeAddress(addressFromPick(flow.address, place));
              _toPin();
            },
          ),
          const SizedBox(height: MyazaSpacing.md),
          CurrentLocationRow(
            hint: flow.fix?.label,
            locating: flow.locating,
            onTap: () => flow.applyCurrentFix(onDone: _toPin),
          ),
          const SizedBox(height: MyazaSpacing.md),
          Center(
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: _toPin,
                borderRadius: BorderRadius.circular(MyazaRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: MyazaSpacing.sm, horizontal: MyazaSpacing.sm),
                  child: Text(
                    'Place a pin on the map instead',
                    style: text.bodyMedium.copyWith(
                      color: colors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          buildError(context),
          buildSkip(context),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
