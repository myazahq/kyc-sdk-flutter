import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/map_frame.dart' show streetViewFrameUrlOf;
import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';
import '../../widgets/myaza_button.dart';
import '../../widgets/sticky_actions.dart';
import 'address_entrance_framing.dart';
import 'address_flow_scaffold.dart';
import 'address_photo_dropzone.dart';
import 'address_photo_picker.dart';
import 'framed_street_view.dart';

// ─── The entrance step ───────────────────────────────────────────────────────
//
// Street View FIRST: it opens automatically wherever Google has photographed
// the street, because framing beats fumbling for a camera, and the applicant's
// own photo is the fallback (no coverage, or they skip). Capturing a frame
// advances straight to review. The panorama reaches a phone the way the map
// does: the hosted /embed/street-view page in a WebView on the app grant
// (FramedStreetView). Mirrors the web and RN SDKs' AddressEntranceStep.

class AddressEntranceStep extends ConsumerStatefulWidget {
  const AddressEntranceStep({super.key});

  @override
  ConsumerState<AddressEntranceStep> createState() =>
      _AddressEntranceStepState();
}

class _AddressEntranceStepState extends ConsumerState<AddressEntranceStep>
    with AddressFlowScaffold<AddressEntranceStep> {
  bool _framing = false;
  bool _skipped = false;

  @override
  KYCStep get step => KYCStep.addressEntrance;

  String? get _svFrameUrl {
    final mapsFrameUrl = flow.state.serverConfig.mapsFrameUrl;
    return mapsFrameUrl == null ? null : streetViewFrameUrlOf(mapsFrameUrl);
  }

  /// Street View can be shown: offered by the flow, a pin to look from, and
  /// either the sandbox stand-in or a framed page to load.
  bool get _streetView =>
      flow.streetViewOffered &&
      flow.pin != null &&
      (flow.vendorsStubbed || _svFrameUrl != null);

  @override
  void initState() {
    super.initState();
    _framing = _streetView;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      flow.notifier.setAddressEntranceFraming(_framing);
      // Nothing to capture here: no framer and the photo input off means there
      // is no decision to make, so move on rather than showing an empty screen.
      if (!_framing && flow.photoMode == 'off') flow.goNext();
    });
  }

  @override
  void dispose() {
    // Not through `flow.notifier` (the mixin disposes the controller first);
    // the flag is transient and the next mount sets it again anyway.
    ref.read(kYCNotifierProvider.notifier).setAddressEntranceFraming(false);
    super.dispose();
  }

  void _toPhoto({required bool skipped}) {
    if (!mounted) return;
    setState(() {
      _framing = false;
      _skipped = skipped;
    });
    flow.notifier.setAddressEntranceFraming(false);
    // The photo input is off too: nothing left to capture, carry on.
    if (flow.photoMode == 'off') flow.goNext();
  }

  Future<void> _pick() async {
    final result = await pickAddressPhoto(context);
    if (!mounted) return;
    if (result.error != null) {
      flow.setError(result.error);
      return;
    }
    final photo = result.photo;
    if (photo == null) return;
    await flow.uploadPhoto(photo.bytes, photo.mimeType, photo.path);
  }

  @override
  Widget buildBody(BuildContext context) {
    final pin = flow.pin;
    if (_framing && _streetView && pin != null) {
      final svRequired = flow.cfg?.streetView == 'required';
      if (flow.vendorsStubbed) {
        return AddressEntrancePlaceholder(
          hideSkip: svRequired,
          onSkip: () => _toPhoto(skipped: true),
          onUse: flow.goNext,
        ).animate().fadeIn(duration: 250.ms);
      }
      return FramedStreetView(
        frameUrl: _svFrameUrl!,
        pin: pin,
        hideSkip: svRequired,
        onCaptured: (frame) {
          flow.patchAddress((a) => a.copyWith(streetView: frame));
          flow.goNext();
        },
        onSkip: () => _toPhoto(skipped: true),
        onUnavailable: () => _toPhoto(skipped: false),
      ).animate().fadeIn(duration: 250.ms);
    }
    if (flow.photoMode == 'off') return const SizedBox.shrink();

    final text = context.myazaText;
    final colors = context.myazaColors;
    final uploaded = flow.state.mediaIds.addressPhoto != null;
    final required = flow.photoMode == 'required';
    final canContinue = !flow.uploading && (!required || uploaded);

    return StickyActions(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_skipped)
            Padding(
              padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
              child: Text(
                'No problem. A quick photo of the entrance works just as well.',
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          AddressPhotoDropzone(
            required: required,
            uploaded: uploaded,
            uploading: flow.uploading,
            previewPath: flow.state.addressPhotoPreview,
            onPick: _pick,
            onRemove: flow.removePhoto,
          ),
          buildError(context),
        ],
      ),
      actions: MyazaButton(
        // A photo is optional unless the workflow says otherwise, and the
        // button says which: pressing on without one is a choice the
        // applicant should be able to read, not guess at.
        label: uploaded || required ? 'Continue' : 'Continue without a photo',
        onPressed: canContinue ? flow.goNext : null,
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
