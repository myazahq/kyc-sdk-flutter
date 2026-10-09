import 'package:flutter/material.dart';

import '../config/signature.dart';
import '../widgets/myaza_button.dart';
import '../widgets/signature_pad.dart';
import '../widgets/signature_pad_parts.dart';

// The sign-on-screen half of a supporting document: the pad, and one button
// that keeps what was drawn. The button stays disabled until there is real
// ink, so nobody saves a dot. MIRRORS the web SDK's SupportingDocumentSignature.
// The wording is fixed: only the texts in the shared customisable contract go
// through the text catalogue.

class SupportingDocumentSignature extends StatefulWidget {
  const SupportingDocumentSignature({
    super.key,
    required this.label,
    required this.saving,
    required this.onSave,
    this.onUploadInstead,
    this.initial,
  });

  final String label;
  final bool saving;

  /// The signature being edited, when there is one.
  final SignatureDrawing? initial;
  final ValueChanged<SignatureDrawing> onSave;

  /// Offered when the workflow also takes a photo of a signature on paper.
  final VoidCallback? onUploadInstead;

  @override
  State<SupportingDocumentSignature> createState() =>
      _SupportingDocumentSignatureState();
}

class _SupportingDocumentSignatureState
    extends State<SupportingDocumentSignature> {
  late SignatureDrawing? _drawing = widget.initial;

  @override
  Widget build(BuildContext context) {
    final ready = _drawing?.hasSignature ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SignaturePad(
          label: 'Sign here: ${widget.label}',
          hint: 'Sign here with your index finger',
          clearLabel: 'Clear',
          enabled: !widget.saving,
          initial: widget.initial,
          onChanged: (drawing) => setState(() => _drawing = drawing),
        ),
        const SizedBox(height: 8),
        MyazaButton(
          label: widget.saving ? 'Saving…' : 'Use this signature',
          isLoading: widget.saving,
          onPressed:
              ready && !widget.saving ? () => widget.onSave(_drawing!) : null,
        ),
        if (widget.onUploadInstead != null) ...[
          const SizedBox(height: 8),
          SignatureTextAction(
            label: 'Upload a photo of your signature instead',
            fullWidth: true,
            onPressed: widget.saving ? null : widget.onUploadInstead,
          ),
        ],
      ],
    );
  }
}
