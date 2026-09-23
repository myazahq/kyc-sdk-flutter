import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supporting_documents.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart';
import '../services/api_service.dart';
import '../widgets/myaza_button.dart';
import 'document_pick.dart';
import 'supporting_document_card.dart';

// ─── Supporting documents screen ──────────────────────────────────────────────
//
// Artefacts the organisation keeps ON FILE, each one named by the org with its
// own guidance. These are NOT the identity evidence this verification is
// decided on: by the time the applicant reaches this screen they have already
// been checked against the government record, so a document that cannot be
// read costs them nothing. The server records it and the verification stands
// on the lookup.
//
// WHICH documents are asked for depends on the ID they picked — a document may
// exist only because they used a particular ID — so the screen is only in the
// step order when that resolution produced something (step_order.dart).
//
// Each card names the values that will be read off that document, because a
// supporting document is whatever the organisation called it: a slot with a
// title alone says nothing about what handing it over is FOR.
//
// The sources and the Continue rule are the business-documents screen's, 1:1,
// so uploading a document feels the same everywhere in the flow.

class SupportingDocumentsScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const SupportingDocumentsScreen({super.key, this.onError});

  @override
  ConsumerState<SupportingDocumentsScreen> createState() =>
      _SupportingDocumentsScreenState();
}

class _SupportingDocumentsScreenState
    extends ConsumerState<SupportingDocumentsScreen> {
  String? _uploadingKey;
  final Map<String, String> _errors = {};

  // In-memory previews for tap-to-check (lost on remount — the row then
  // degrades to the plain uploaded state; the mediaId is what matters).
  final Map<String, Uint8List> _previews = {};
  final Set<String> _pdfKeys = {};

  Future<void> _pick(String key) async {
    setState(() => _errors.remove(key));
    final result = await pickDocument(context, slotKey: key);
    if (!mounted) return;
    if (result.error != null) {
      _fail(key, result.error!);
      return;
    }
    final file = result.file;
    if (file == null) return; // cancelled
    await _upload(key, file);
  }

  Future<void> _upload(String key, PickedDocument file) async {
    final sizeError = uploadSizeError(file.mimeType, file.bytes.length);
    if (sizeError != null) {
      _fail(key, sizeError);
      return;
    }
    final isPdf = file.mimeType == 'application/pdf';
    setState(() {
      _uploadingKey = key;
      _previews.remove(key);
      _pdfKeys.remove(key);
      if (isPdf) {
        _pdfKeys.add(key);
      } else {
        _previews[key] = file.bytes;
      }
    });
    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final mediaId = await notifier.api
          .upload(file.bytes, file.mimeType, MediaType.supportingDocument);
      if (!mounted) return;
      notifier.setSupportingDocument(
        SupportingDocumentUpload(
          type: key,
          mediaId: mediaId,
          fileName: file.fileName,
          previewPath: file.previewPath,
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
    ref.read(kYCNotifierProvider.notifier).removeSupportingDocument(key);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(kycConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final slots = resolveSupportingDocuments(
      config.supportingDocuments,
      verifiedIdComposites(config, state),
    );
    final uploads = state.supportingDocuments;

    SupportingDocumentUpload? uploadFor(String key) {
      for (final u in uploads) {
        if (u.type == key) return u;
      }
      return null;
    }

    final requiredComplete =
        slots.every((s) => !s.required || uploadFor(s.key) != null);
    // Nothing is required and nothing has been added: the honest label is
    // Skip, not Continue — pressing on is a deliberate choice to add nothing.
    final optionalOnly = slots.every((s) => !s.required);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, slot) in slots.indexed)
          SupportingDocumentCard(
            position: index + 1,
            total: slots.length,
            label: slot.label,
            description: slot.description,
            required: slot.required,
            reads: slot.reads,
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
          label: optionalOnly && uploads.isEmpty ? 'Skip' : 'Continue',
          onPressed: requiredComplete && _uploadingKey == null
              ? () => ref.read(kYCNotifierProvider.notifier).nextStep()
              : null,
        ),
      ],
    );
  }
}
