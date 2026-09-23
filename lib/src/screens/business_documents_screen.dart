import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/myaza_button.dart';
import '../config/upload_limits.dart';
import 'business_document_slot.dart';
import 'document_pick.dart';

part 'business_documents_pick.dart';

// ─── Business documents screen ────────────────────────────────────────────────
//
// One upload slot per document type the workflow configures. Each file uploads
// immediately (type `business_document`) and its mediaId is stored in flow
// state; Continue is blocked until every REQUIRED slot has one. The uploads
// ride the business /verify submission as `business.documents`.
//
// Mirrors the web SDK's BusinessDocumentsStep. Files come from the photo
// library, the camera, or Files (the only path that can supply a PDF), through
// the shared picker in document_pick.dart; business_documents_pick.dart is the
// thin part that hands the result to this screen's own upload.

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

  void _rebuild(VoidCallback fn) => setState(fn);

  Future<void> _upload(
    String key,
    Uint8List bytes,
    String mime,
    String name, {
    String? previewPath,
  }) async {
    final sizeError = uploadSizeError(mime, bytes.length);
    if (sizeError != null) {
      _fail(key, sizeError);
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
