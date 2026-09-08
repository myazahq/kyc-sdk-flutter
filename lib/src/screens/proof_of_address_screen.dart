import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/poa_country_gate.dart';
import '../config/proof_of_address.dart';
import '../config/scope.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/address_country_control.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/myaza_button.dart';
import 'proof_of_address_kinds.dart';
import 'proof_of_address_parts.dart';
import 'proof_of_address_pick.dart';

part 'proof_of_address_upload.dart';

// ─── Proof of Address screen ──────────────────────────────────────────────────
//
// Collects a proof-of-address document (image or PDF) after capture. A soft
// server-side check — it never changes the verification's own status. The user
// picks from the photo library, the camera, or Files (jpg/png/webp/pdf): the
// native equivalent of the web SDK's `<input type=file accept=image/*,pdf>`.
//
// The UI mirrors the web SDK: a DASHED drop zone that names the document being
// asked for ("Upload your utility bill") and what's accepted, replaced after
// upload by a row showing the file, its kind, and an X to remove it.

class ProofOfAddressScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const ProofOfAddressScreen({super.key, this.onError});

  @override
  ConsumerState<ProofOfAddressScreen> createState() =>
      _ProofOfAddressScreenState();
}

class _ProofOfAddressScreenState extends ConsumerState<ProofOfAddressScreen> {
  PoaDocumentType? _type;
  bool _uploading = false;
  String? _fileName;
  String? _error;

  // Kept so the uploaded row can show the user what they actually picked —
  // the only way to catch "wrong photo from the camera roll" before submitting.
  Uint8List? _previewBytes;
  bool _previewIsPdf = false;

  ProofOfAddressConfig get _cfg =>
      ref.read(kycConfigProvider).proofOfAddress ??
      const ProofOfAddressConfig(enabled: true);

  /// The country the document is for — on the address scope the control at
  /// the top of this screen changes it, and an org may accept different
  /// papers per market.
  String? get _country =>
      ref.read(kYCNotifierProvider).selectedCountry ??
      ref.read(kycConfigProvider).country;

  @override
  void initState() {
    super.initState();
    final offered = _cfg.offeredTypesFor(_country);
    _type = offered.isNotEmpty ? offered.first : PoaDocumentType.other;
  }

  String get _typeLabel => _cfg.labelFor(_type ?? PoaDocumentType.other);

  /// `setState` for the upload ops in the part file: a protected member may
  /// only be called from the State itself, so the extension goes through this.
  void _rebuild(VoidCallback fn) => setState(fn);

  Future<void> _pick() async {
    setState(() => _error = null);
    final source = await showMediaSourceSheet(context);
    if (source == null || !mounted) return;
    try {
      final picked = switch (source) {
        MediaSource.photoLibrary => await pickPoaImage(ImageSource.gallery),
        MediaSource.camera => await pickPoaImage(ImageSource.camera),
        MediaSource.files => await pickPoaFile(),
      };
      if (picked == null || !mounted) return; // cancelled
      await _upload(picked.bytes, picked.mime, picked.name);
    } on PoaPickException catch (e) {
      _failUpload(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final selectedCountry = ref.watch(kYCNotifierProvider).selectedCountry;
    final config = ref.watch(kycConfigProvider);
    final offered = _cfg.offeredTypesFor(selectedCountry ?? config.country);
    // The flag on the attachment area: on the address scope only a country the
    // applicant picked (the scope has no seeded country to show), else the
    // flow's effective country.
    final flagCountry = configScope(config.scope) == 'address'
        ? selectedCountry
        : (selectedCountry ?? config.country);
    // A country change can withdraw the picked kind; fall back to the first
    // offered rather than submitting a label that country does not accept.
    ref.listen(kYCNotifierProvider.select((s) => s.selectedCountry), (_, __) {
      final now = _cfg.offeredTypesFor(_country);
      if (_type != null && !now.contains(_type)) {
        setState(() =>
            _type = now.isNotEmpty ? now.first : PoaDocumentType.other);
      }
    });
    final uploaded =
        ref.watch(kYCNotifierProvider).mediaIds.proofOfAddress != null;
    // The address scope's country is the applicant's declaration and drives
    // the document's market; Continue holds until it is made (the control
    // above asks for it). Never bites elsewhere. See poa_country_gate.dart.
    final countryDeclared = poaCountryDeclared(
      scope: configScope(config.scope),
      selectedCountry: selectedCountry,
      offered: poaOfferedCountries(config.proofOfAddress?.countries ?? const []),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The declared-country picker — renders nothing outside the address
        // scope.
        const AddressCountryControl(),

        // ── Document type picker (only when >1 offered) ──────────────────────
        //
        // Locked once a file is attached: switching the kind afterwards would
        // mislabel the document already uploaded.
        if (offered.length > 1) ...[
          Text('Document type', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          PoaDocumentTypeList(
            options: offered,
            value: _type,
            enabled: !uploaded && !_uploading,
            labelFor: _cfg.labelFor,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: MyazaSpacing.lg),
        ],

        // ── Drop zone / uploaded row ─────────────────────────────────────────
        if (uploaded && !_uploading)
          PoaUploadedRow(
            fileName: _fileName ?? 'Document uploaded',
            typeLabel: _typeLabel,
            previewBytes: _previewBytes,
            isPdf: _previewIsPdf,
            country: flagCountry,
            onRemove: _remove,
          )
        else
          PoaDropzone(
            uploading: _uploading,
            typeLabel: _typeLabel,
            country: flagCountry,
            onTap: _pick,
          ),

        if (_error != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(_error!,
              style: text.bodySmall.copyWith(color: MyazaColors.error)),
        ],

        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: 'Continue',
          onPressed: uploaded && !_uploading && countryDeclared
              ? () => ref.read(kYCNotifierProvider.notifier).nextStep()
              : null,
        ),
      ],
    );
  }
}
