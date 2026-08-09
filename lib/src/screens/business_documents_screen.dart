import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/myaza_button.dart';
import 'business_document_slot.dart';

// ─── Business documents screen ────────────────────────────────────────────────
//
// One upload slot per document type the workflow configures. Each file uploads
// immediately (type `business_document`) and its mediaId is stored in flow
// state; Continue is blocked until every REQUIRED slot has one. The uploads
// ride the business /verify submission as `business.documents`.
//
// Mirrors the web SDK's BusinessDocumentsStep. Files come from the photo
// library, the camera, or Files (the only path that can supply a PDF).

const _kAllowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

/// Server cap is 25MB; stay under it so a rejected upload is caught locally
/// with a clear message instead of a 413.
const int kBusinessDocMaxBytes = 20 * 1024 * 1024;

class BusinessDocumentsScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const BusinessDocumentsScreen({super.key, this.onError});

  @override
  ConsumerState<BusinessDocumentsScreen> createState() =>
      _BusinessDocumentsScreenState();
}

class _BusinessDocumentsScreenState
    extends ConsumerState<BusinessDocumentsScreen> {
  String? _uploadingKey;
  final Map<String, String> _errors = {};

  // In-memory previews for tap-to-check (lost on remount — the row then degrades
  // to the plain uploaded state; the mediaId in flow state is what matters).
  final Map<String, Uint8List> _previews = {};
  final Set<String> _pdfKeys = {};

  String _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  Future<void> _pick(String key) async {
    setState(() => _errors.remove(key));
    final source = await showMediaSourceSheet(context);
    if (source == null || !mounted) return;
    switch (source) {
      case MediaSource.photoLibrary:
        await _pickImage(key, ImageSource.gallery);
      case MediaSource.camera:
        await _pickImage(key, ImageSource.camera);
      case MediaSource.files:
        await _pickFile(key);
    }
  }

  Future<void> _pickImage(String key, ImageSource source) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      // A FRIENDLY name, not the picker's temp junk: iOS's image_picker names
      // its copy `image_picker_<UUID>.png` (the photo library does not expose
      // the original), which reads as noise on the uploaded card. The slot key
      // says what the file IS — `incorporation_certificate.jpg`.
      final ext = picked.name.split('.').lastOrNull ?? 'jpg';
      await _upload(key, bytes, _mimeFor(ext), '$key.${ext.toLowerCase()}',
          previewPath: picked.path);
    } catch (_) {
      _fail(key, 'Could not read that photo. Please try another.');
    }
  }

  /// Files — the only source that can supply a PDF.
  Future<void> _pickFile(String key) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kAllowedExtensions,
        withData: true,
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || !mounted) return; // cancelled
      await _upload(key, bytes, _mimeFor(file.extension), file.name);
    } catch (_) {
      _fail(key, 'Could not read that file. Please try another.');
    }
  }

  Future<void> _upload(
    String key,
    Uint8List bytes,
    String mime,
    String name, {
    String? previewPath,
  }) async {
    if (bytes.length > kBusinessDocMaxBytes) {
      _fail(key, 'File is too large (max 20MB).');
      return;
    }
    final isPdf = mime == 'application/pdf';
    setState(() {
      _uploadingKey = key;
      _previews.remove(key);
      _pdfKeys.remove(key);
      if (isPdf) {
        _pdfKeys.add(key);
      } else {
        _previews[key] = bytes;
      }
    });
    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final mediaId =
          await notifier.api.upload(bytes, mime, MediaType.businessDocument);
      if (!mounted) return;
      notifier.setBusinessDocument(
        BusinessDocumentUpload(
          type: key,
          mediaId: mediaId,
          fileName: name,
          // On the record, so the thumbnail survives leaving the step —
          // screen-local preview state dies with the widget.
          previewPath: previewPath,
          isPdf: isPdf,
        ),
      );
      setState(() => _uploadingKey = null);
    } on KYCApiException catch (e) {
      _fail(key, e.message ?? 'Upload failed. Please try again.');
      widget.onError?.call(e);
    } catch (_) {
      _fail(key, 'Upload failed. Please try again.');
    }
  }

  void _fail(String key, String message) {
    if (!mounted) return;
    setState(() {
      _uploadingKey = null;
      _previews.remove(key);
      _pdfKeys.remove(key);
      _errors[key] = message;
    });
  }

  void _remove(String key) {
    setState(() {
      _previews.remove(key);
      _pdfKeys.remove(key);
      _errors.remove(key);
    });
    ref.read(kYCNotifierProvider.notifier).removeBusinessDocument(key);
  }

  @override
  Widget build(BuildContext context) {
    final slots =
        resolveBusinessDocumentTypes(ref.watch(kycConfigProvider).business);
    final uploads = ref.watch(kYCNotifierProvider).businessDocuments;

    BusinessDocumentUpload? uploadFor(String key) {
      for (final u in uploads) {
        if (u.type == key) return u;
      }
      return null;
    }

    final requiredComplete =
        slots.every((s) => !s.required || uploadFor(s.key) != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No lead paragraph: the step HEADER carries "Upload the supporting
        // documents…" (myaza_kyc_widget.dart step meta, matching the web SDK's
        // StepHeader) — repeating it here read as two descriptions stacked.
        for (final slot in slots)
          BusinessDocumentSlot(
            label: slot.label,
            required: slot.required,
            fileName: uploadFor(slot.key)?.fileName,
            previewBytes: _previews[slot.key],
            previewPath: uploadFor(slot.key)?.previewPath,
            isPdf: _pdfKeys.contains(slot.key) ||
                (uploadFor(slot.key)?.isPdf ?? false),
            uploading: _uploadingKey == slot.key,
            error: _errors[slot.key],
            onTap: () => _pick(slot.key),
            onRemove: () => _remove(slot.key),
          ),

        const SizedBox(height: MyazaSpacing.lg),
        MyazaButton(
          label: 'Continue',
          onPressed: requiredComplete && _uploadingKey == null
              ? () => ref.read(kYCNotifierProvider.notifier).nextStep()
              : null,
        ),
      ],
    );
  }
}
