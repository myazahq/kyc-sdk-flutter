import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/address_collection.dart';
import '../../config/address_field_modes.dart';
import '../../config/address_flow.dart';
import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';
import '../../utils/address_current_location.dart';
import '../../utils/map_tiles.dart' show mapSurfaceHeight;
import '../../widgets/framed_map_picker.dart';
import '../../widgets/myaza_button.dart';
import '../../widgets/sticky_actions.dart';
import 'address_details_sheet.dart';
import 'address_flow_scaffold.dart';
import 'address_label_decision.dart';
import 'address_location_row.dart';
import 'address_map_stub.dart';
import 'address_pin_summary.dart';

// ─── The PIN step (wire name 'address-collection') ───────────────────────────
//
// A big map (sized by mapSurfaceHeight, so a phone keeps room to scroll), with
// the summary card and the details sheet under it, and Continue held at the
// bottom edge (StickyActions) so the map can never put it out of reach. On
// KYB this is the WHOLE premises capture, so Continue commits; on individual
// flows it advances to the entrance and review steps. Workflow-required
// details hold Continue and open the sheet on the missing fields rather than
// pointing at a closed drawer.
//
// The wire name is deliberately the original one even though this is now the
// second screen: session progress saved by older builds restores cleanly onto
// it and the server's step-log titles stay meaningful.

class AddressPinStep extends ConsumerStatefulWidget {
  const AddressPinStep({super.key});

  @override
  ConsumerState<AddressPinStep> createState() => _AddressPinStepState();
}

class _AddressPinStepState extends ConsumerState<AddressPinStep>
    with AddressFlowScaffold<AddressPinStep> {
  bool _missingNudge = false;

  @override
  KYCStep get step => KYCStep.addressCollection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMount());
  }

  void _onMount() {
    if (!mounted) return;
    // The fix warms even under the primer: only the APPLY waits for it, since
    // a pin landing behind the primer would be invisible anyway.
    flow.startPrefetch();
    if (flow.showIntroGate(step)) return;
    // A restored pin without its line (a session saved before labels existed):
    // reverse-geocode it once rather than showing raw coordinates.
    if (flow.address != null) {
      flow.relabelPin();
      return;
    }
    // Most people are verifying from home, so the map should land on them
    // rather than a city-centre default. Silent by contract, and claimed once
    // per flow: a dismissed or denied prompt must not re-fire every time they
    // pass back through this step.
    if (claimAutoLocate()) flow.applyCurrentFix(silent: true);
  }

  @override
  void onGateCleared() {
    // The primer stood in front of this step's mount work; now it is gone,
    // run it. _onMount re-checks the gate itself, so this cannot double-run.
    _onMount();
  }

  void _openDetails() {
    final address = flow.address;
    if (address == null) return;
    showAddressDetailsSheet(
      context,
      isBusiness: flow.isBusiness,
      directionsRequired: addressDirectionsMode(flow.cfg) == 'required',
      parts: address.parts,
      country: flow.country,
      address: address,
      config: flow.cfg,
      onChanged: (patch) => flow.patchAddress((a) => a.copyWith(
            street: patch.street,
            propertyNumber: patch.propertyNumber,
            unit: patch.unit,
            propertyName: patch.propertyName,
            directions: patch.directions,
            neighbourhood: patch.neighbourhood,
            city: patch.city,
            state: patch.state,
            postcode: patch.postcode,
          )),
    );
  }

  void _continue() {
    if (missingRequiredAddressFields(flow.cfg, flow.address).isNotEmpty) {
      setState(() => _missingNudge = true);
      _openDetails();
      return;
    }
    // Whoever is last commits. On KYB that is this step (the premises pin and
    // its directions ARE the capture); on individual flows the review owns it.
    // Read off the flow's own step list rather than the subject type, so the
    // attest fix and the presence pin follow the flow rather than an
    // assumption about its shape.
    if (flow.isLastAddressStep(step)) {
      flow.confirm();
    } else {
      flow.goNext();
    }
  }

  @override
  Widget buildBody(BuildContext context) {
    final address = flow.address;
    final pin = flow.pin;
    final label = address?.label;
    final askLabel = address != null && shouldAskLabelDecision(address);
    final missing = missingRequiredAddressFields(flow.cfg, address);
    final mapHeight = mapSurfaceHeight(MediaQuery.sizeOf(context));

    return StickyActions(
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyazaButton(
            label: 'Continue',
            isLoading: flow.confirming,
            onPressed: pin == null || flow.confirming ? null : _continue,
          ),
          buildSkip(context),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The framed Google picker when the platform serves one; the OSM
          // picker otherwise (and whenever the page never says ready). A
          // SANDBOX mount loads neither: the placeholder stands in, and the
          // pin lands on the default centre so the flow still walks.
          if (flow.vendorsStubbed)
            AddressMapStub(hasPin: pin != null, onLand: flow.setPin, defaultCenter: flow.view.center, height: mapHeight)
          else
            FramedMapPicker(
              frameUrl: ref.watch(kYCNotifierProvider.select((s) => s.serverConfig.mapsFrameUrl)),
              value: pin,
              onChange: flow.setPin,
              defaultCenter: flow.view.center,
              defaultZoom: flow.view.zoom,
              height: mapHeight,
              overlay: pin == null ? null : LocateOnMapButton(locating: flow.locating, onTap: flow.locateToPin),
            ),
          const SizedBox(height: MyazaSpacing.md),
          AddressPinSummary(
            address: address,
            labelling: flow.labelling,
            onEdit: pin == null ? null : _openDetails,
          ),
          if (askLabel && label != null) ...[
            const SizedBox(height: MyazaSpacing.md),
            AddressLabelDecision(label: label, onKeep: flow.keepPickedLabel, onAdopt: flow.adoptPinAddress),
          ],
          if (pin == null) ...[
            const SizedBox(height: MyazaSpacing.md),
            CurrentLocationRow(hint: flow.fix?.label, locating: flow.locating, onTap: flow.applyCurrentFix),
          ],
          buildError(context),
          if (_missingNudge && missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MyazaSpacing.sm),
              child: Text(missingFieldsNudge(missing),
                  style: context.myazaText.bodySmall.copyWith(color: MyazaColors.error)),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
