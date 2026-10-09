import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/signature.dart';
import '../config/supporting_documents.dart';
import '../config/theme.dart';
import '../widgets/signature_preview.dart';
import '../widgets/supporting_document_parts.dart';
import 'business_document_slot.dart';
import 'supporting_document_signature.dart';

// ─── One requested supporting document ───────────────────────────────────────
//
// What it is, what it is being taken FOR, and the upload that satisfies it.
//
// The middle part is the point. A supporting document is whatever the
// organisation named it, so an upload slot with a title on it tells the
// applicant almost nothing; naming the values that will be read off it says
// what the document is actually for, and is the honest thing to show somebody
// before they hand over a bank statement.
//
// MIRRORS the web SDK's SupportingDocumentCard. Keep the two in step.

class SupportingDocumentCard extends StatefulWidget {
  const SupportingDocumentCard({
    super.key,
    required this.position,
    required this.total,
    required this.label,
    required this.description,
    required this.required,
    required this.reads,
    required this.fileName,
    required this.uploading,
    this.previewBytes,
    this.previewPath,
    this.isPdf = false,
    this.error,
    this.onTap,
    this.onRemove,
    this.capture = SupportingDocumentCapture.upload,
    this.drawn = false,
    this.onSign,
  });

  /// How it is provided: a file, a signature drawn on screen, or either.
  final SupportingDocumentCapture capture;

  /// The provided document was signed on screen.
  final bool drawn;
  final ValueChanged<SignatureDrawing>? onSign;

  /// 1-based, so the list reads as a checklist rather than a pile.
  final int position;
  final int total;
  final String label;

  /// Guidance the organisation wrote: which document, and what it has to show.
  final String? description;
  final bool required;

  /// The named values the server will read off it, in the author's words.
  final List<String> reads;

  final String? fileName;
  final Uint8List? previewBytes;
  final String? previewPath;
  final bool isPdf;
  final bool uploading;
  final String? error;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  State<SupportingDocumentCard> createState() => _SupportingDocumentCardState();
}

class _SupportingDocumentCardState extends State<SupportingDocumentCard> {
  // Where the workflow offers both, the pad comes first: it is the shorter way.
  bool _uploadInstead = false;

  // What was signed, kept so it can be shown once saved and reopened by Edit.
  // It lives only as long as this screen: a resumed session shows the pen mark.
  SignatureDrawing? _signed;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final position = widget.position;
    final total = widget.total;
    final label = widget.label;
    final description = widget.description;
    final required = widget.required;
    final reads = widget.reads;
    final fileName = widget.fileName;
    final uploading = widget.uploading;
    final error = widget.error;
    final capture = widget.capture;
    final done = fileName != null && !uploading;
    final both = capture == SupportingDocumentCapture.drawOrUpload;
    final signing = capture != SupportingDocumentCapture.upload &&
        !_uploadInstead &&
        fileName == null &&
        widget.onSign != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: MyazaSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          // The card is the LIFTED surface and the wells inside it are the page
          // colour — the web SDK's arrangement (`bg-secondary` card over a
          // `bg-background` well). These were the other way round here, so the
          // card read as the page and its wells floated above it.
          color: done ? colors.primary50 : colors.backgroundSecondary,
          border: Border.all(color: done ? colors.primary200 : colors.border),
          borderRadius: BorderRadius.circular(MyazaRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(MyazaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DocumentMarker(
                          done: done, position: position, total: total),
                      const SizedBox(width: MyazaSpacing.sm + 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: text.label
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (description != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: text.bodySmall.copyWith(
                                  color:
                                      colors.textDark.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: MyazaSpacing.sm),
                      DocumentStatePill(required: required),
                    ],
                  ),
                  if (reads.isNotEmpty) ...[
                    const SizedBox(height: MyazaSpacing.sm + 4),
                    DocumentReads(reads: reads),
                  ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(MyazaSpacing.sm + 4),
              child: signing
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SupportingDocumentSignature(
                          label: label,
                          saving: uploading,
                          initial: _signed,
                          onSave: (drawing) {
                            setState(() => _signed = drawing);
                            widget.onSign!(drawing);
                          },
                          onUploadInstead: both
                              ? () => setState(() => _uploadInstead = true)
                              : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: MyazaSpacing.sm),
                          Text(error,
                              style: text.bodySmall
                                  .copyWith(color: MyazaColors.error)),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.drawn && done) ...[
                          SignedSignatureRow(
                            drawing: _signed,
                            label: label,
                            // Edit reopens the pad with the signature in it.
                            onEdit: widget.onRemove,
                            onRemove: () {
                              setState(() => _signed = null);
                              widget.onRemove?.call();
                            },
                          ),
                          if (error != null) ...[
                            const SizedBox(height: MyazaSpacing.sm),
                            Text(error,
                                style: text.bodySmall
                                    .copyWith(color: MyazaColors.error)),
                          ],
                        ] else
                          BusinessDocumentSlot(
                            label: label,
                            required: required,
                            fileName: fileName,
                            previewBytes: widget.previewBytes,
                            previewPath: widget.previewPath,
                            isPdf: widget.isPdf,
                            uploading: uploading,
                            error: error,
                            onTap: widget.onTap,
                            onRemove: widget.onRemove,
                            compact: true,
                          ),
                        if (both && _uploadInstead && fileName == null)
                          TextButton(
                            onPressed: uploading
                                ? null
                                : () => setState(() => _uploadInstead = false),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: colors.primary,
                            ),
                            child: const Text('Sign on screen instead'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
