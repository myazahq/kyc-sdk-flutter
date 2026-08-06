import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/proof_of_address.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_select.dart';
import 'proof_of_address_parts.dart';

// ─── Proof of Address screen ──────────────────────────────────────────────────
//
// Collects a proof-of-address document (image or PDF) after capture. A soft
// server-side check — it never changes the verification's own status. The user
// picks from the photo library, the camera, or Files (jpg/png/webp/pdf): the
// native equivalent of the web SDK's `<input type=file accept=image/*,pdf>`.

const _kAllowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

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

  @override
  void initState() {
    super.initState();
    final offered = _cfg.offeredTypes;
    _type = offered.isNotEmpty ? offered.first : PoaDocumentType.other;
  }

  String _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  Future<void> _pick() async {
    setState(() => _error = null);
    final source = await showMediaSourceSheet(context);
    if (source == null || !mounted) return;
    switch (source) {
      case MediaSource.photoLibrary:
        await _pickImage(ImageSource.gallery);
      case MediaSource.camera:
        await _pickImage(ImageSource.camera);
      case MediaSource.files:
        await _pickFile();
    }
  }

  /// Camera roll / camera — always an image, so the mime comes from the name.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final ext = picked.name.split('.').lastOrNull;
      await _upload(bytes, _mimeFor(ext), picked.name);
    } catch (e) {
      _failUpload('Could not read that photo. Please try another.');
    }
  }

  /// Files — the only path that can supply a PDF.
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kAllowedExtensions,
        withData: true,
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || !mounted) return; // cancelled
      await _upload(bytes, _mimeFor(file.extension), file.name);
    } catch (e) {
      _failUpload('Could not read that file. Please try another.');
    }
  }

  Future<void> _upload(Uint8List bytes, String mime, String name) async {
    final isPdf = mime == 'application/pdf';
    setState(() {
      _uploading = true;
      _fileName = name;
      _previewIsPdf = isPdf;
      // Only images are renderable; a PDF falls back to the document tile.
      _previewBytes = isPdf ? null : bytes;
    });
    try {
      final api = ref.read(kYCNotifierProvider.notifier).api;
      final mediaId =
          await api.upload(bytes, mime, MediaType.proofOfAddress);
      if (!mounted) return;
      ref
          .read(kYCNotifierProvider.notifier)
          .setProofOfAddress(mediaId, (_type ?? PoaDocumentType.other).key);
      setState(() => _uploading = false);
    } on KYCApiException catch (e) {
      _failUpload(e.message ?? 'Upload failed. Please try again.');
      widget.onError?.call(e);
    } catch (e) {
      _failUpload('Upload failed. Please try again.');
    }
  }

  void _failUpload(String message) {
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _fileName = null;
      _previewBytes = null;
      _previewIsPdf = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final offered = _cfg.offeredTypes;
    final uploaded =
        ref.watch(kYCNotifierProvider).mediaIds.proofOfAddress != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Upload a document issued in the last ${_cfg.maxAgeDays} days that '
          'shows your name and address.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Document type picker (only when >1 offered) ──────────────────────
        if (offered.length > 1) ...[
          Text('Document type', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<PoaDocumentType>(
            value: _type,
            sheetTitle: 'Document type',
            options: [
              for (final t in offered)
                MyazaSelectOption(value: t, label: t.label),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: MyazaSpacing.lg),
        ],

        // ── Picker / uploaded state ──────────────────────────────────────────
        PoaUploadCard(
          uploading: _uploading,
          fileName: uploaded ? _fileName : null,
          previewBytes: _previewBytes,
          isPdf: _previewIsPdf,
          typeLabel: (_type ?? PoaDocumentType.other).label,
          onTap: _uploading ? null : _pick,
        ),
        if (_error != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(_error!,
              style: text.bodySmall.copyWith(color: MyazaColors.error)),
        ],

        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: 'Continue',
          onPressed: uploaded && !_uploading
              ? () => ref.read(kYCNotifierProvider.notifier).nextStep()
              : null,
        ),
      ],
    );
  }
}
