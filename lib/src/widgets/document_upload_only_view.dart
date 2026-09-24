import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'document_upload_target.dart';
import 'myaza_alert.dart';
import 'icons/icons.dart';

// ─── Upload-only document side ────────────────────────────────────────────────
//
// One side of the document step when the workflow turns the camera off
// (`allowDocumentScan: false`): no viewfinder, no permission prompt, just the
// tap target (DocumentUploadTarget) and three tips. There is no picker button:
// the card is the control. Stateless on purpose: the screen owns the pick
// (crop, compress, preview, review, upload) and its busy/error state, so this
// cannot drift from the camera path.

const kDocumentUploadTargetKey = ValueKey('kyc.upload.target');

class DocumentUploadOnlyView extends StatelessWidget {
  final String idTypeLabel;

  /// Which side is being asked for. Only ever true on a two-sided ID.
  final bool isBack;

  /// Document aspect, so the tap target is the shape of what is expected.
  final double aspect;

  /// A pick is being prepared (cropped and compressed). Disables the picker.
  final bool isBusy;

  /// Why the last pick could not be used, shown above the tap target.
  final String? error;
  final VoidCallback? onDismissError;

  final VoidCallback onPick;

  /// Sits above the tap target (the screen's required-document pill).
  final Widget? header;

  const DocumentUploadOnlyView({
    super.key,
    required this.idTypeLabel,
    required this.isBack,
    required this.aspect,
    required this.isBusy,
    required this.onPick,
    this.error,
    this.onDismissError,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: MyazaSpacing.md),
        ],
        Expanded(
          child: SingleChildScrollView(
            // Clear of the home indicator, read from the view for the reason
            // DocumentReview gives: an ancestor may have removed the padding.
            padding: EdgeInsets.only(
              bottom:
                  MediaQueryData.fromView(View.of(context)).viewPadding.bottom +
                      MyazaSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  MyazaAlert(
                    variant: MyazaAlertVariant.error,
                    title: "Couldn't use that photo",
                    message: error!,
                    onDismiss: onDismissError,
                  ),
                  const SizedBox(height: MyazaSpacing.sm),
                ],
                DocumentUploadTarget(
                  key: kDocumentUploadTargetKey,
                  idTypeLabel: idTypeLabel,
                  isBack: isBack,
                  aspect: aspect,
                  isBusy: isBusy,
                  hasError: error != null,
                  onPick: onPick,
                ),
                const SizedBox(height: MyazaSpacing.lg),
                const _Tip(MyazaIcons.scan, 'All four corners are in the photo'),
                const _Tip(MyazaIcons.sun, 'No glare, shadows or blur'),
                const _Tip(MyazaIcons.type, 'Every word is easy to read'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final MyazaIconData icon;
  final String label;

  const _Tip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
      child: Row(
        children: [
          MyazaIcon(icon, size: 16, color: colors.primary),
          const SizedBox(width: MyazaSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.myazaText.bodySmall
                  .copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
