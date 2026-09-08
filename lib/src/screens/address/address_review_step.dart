import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'address_sandbox_tabs.dart';
import '../../config/address_field_modes.dart';
import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../services/api_service.dart';
import '../../providers/kyc_state.dart';
import '../../widgets/myaza_button.dart';
import 'address_flow_scaffold.dart';
import 'address_review_card.dart';

/// The commit point: one composed card carrying a read-only map, the entrance
/// imagery clipped to it, and the address as the card's own heading.
///
/// Mirrors the web and RN SDKs' AddressReviewStep. The presence story lives on
/// the intro screen, not here. Workflow-required details the applicant skipped
/// hold Confirm (the pin step's own gate, repeated here as the backstop).
class AddressReviewStep extends ConsumerStatefulWidget {
  const AddressReviewStep({super.key});

  @override
  ConsumerState<AddressReviewStep> createState() => _AddressReviewStepState();
}

class _AddressReviewStepState extends ConsumerState<AddressReviewStep>
    with AddressFlowScaffold<AddressReviewStep> {
  @override
  KYCStep get step => KYCStep.addressReview;

  /// The framed Street View entrance, fetched through the SERVER: the browser
  /// key lives in the framed page, never in this SDK, so a frame captured
  /// there reviewed as nothing at all until it came back this way.
  Uint8List? _streetViewThumb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadStreetViewThumb();
    });
    // A resumed session can land straight here with a pin that predates the
    // label fields: reverse-geocode it once rather than showing coordinates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) flow.relabelPin();
    });
  }

  Future<void> _loadStreetViewThumb() async {
    final frame = flow.address?.streetView;
    if (frame == null) return;
    final bytes = await ref.read(kYCNotifierProvider.notifier).api.addressStreetViewPreview(
          panoId: frame.panoId,
          heading: frame.heading,
          pitch: frame.pitch,
          fov: frame.fov,
        );
    if (mounted && bytes != null) setState(() => _streetViewThumb = bytes);
  }

  void _edit() => ref
      .read(kYCNotifierProvider.notifier)
      .goToStep(KYCStep.addressCollection);

  @override
  Widget buildBody(BuildContext context) {
    final pin = flow.pin;
    final missing = missingRequiredAddressFields(flow.cfg, flow.address);
    final text = context.myazaText;
    // A plain column: the sheet's own scroll view carries this step, as it
    // does on RN, and a second scrollable inside it fought the first.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AddressReviewCard(
            address: flow.address,
            pin: pin,
            isBusiness: flow.isBusiness,
            photoPreviewPath: flow.state.addressPhotoPreview,
            onEdit: _edit,
            vendorsStubbed: flow.vendorsStubbed,
            labelling: flow.labelling,
            streetViewThumb: _streetViewThumb,
            mapsFrameUrl: ref.watch(
              kYCNotifierProvider.select((s) => s.serverConfig.mapsFrameUrl),
            ),
            staticMapUrl: pin == null
                ? null
                : ref
                    .read(kYCNotifierProvider.notifier)
                    .api
                    .staticMapUrl(lat: pin.lat, lng: pin.lng),
            imageHeaders:
                ref.read(kYCNotifierProvider.notifier).api.imageHeaders,
          ),
          buildError(context),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MyazaSpacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MyazaSpacing.xs,
                children: [
                  Text(missingFieldsNudge(missing),
                      style: text.bodySmall.copyWith(color: MyazaColors.error)),
                  GestureDetector(
                    onTap: _edit,
                    child: Text('Edit details',
                        style: text.bodySmall.copyWith(
                          color: context.myazaColors.primary,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
          const SizedBox(height: MyazaSpacing.lg),
          const AddressSandboxTabs(),
          const SizedBox(height: MyazaSpacing.md),
          MyazaButton(
            label: 'Confirm address',
            isLoading: flow.confirming,
            onPressed: pin == null || flow.confirming || missing.isNotEmpty
                ? null
                : flow.confirm,
          ),
          buildSkip(context),
        ],
    ).animate().fadeIn(duration: 250.ms);
  }
}
