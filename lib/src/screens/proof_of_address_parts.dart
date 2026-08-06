import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── Proof of Address — upload card ───────────────────────────────────────────
//
// The tap target that opens the source sheet, and the uploaded state it turns
// into: a thumbnail of what was actually picked, the file name, and the chosen
// document type. Showing the image back matters — it's the only way a user can
// tell they grabbed the right photo out of a camera roll before submitting.
//
// The preview renders the in-memory bytes from the picker (no server round
// trip); PDFs get a document tile instead, since the SDK ships no PDF renderer.

class PoaUploadCard extends StatelessWidget {
  final bool uploading;
  final String? fileName;

  /// Bytes of the picked file, kept for the thumbnail. Null for PDFs or when
  /// nothing has been picked yet.
  final Uint8List? previewBytes;

  /// True when the pick was a PDF — renders a document tile, not an image.
  final bool isPdf;

  /// Selected document type ("Utility bill"), shown under the file name.
  final String? typeLabel;

  final VoidCallback? onTap;

  const PoaUploadCard({
    super.key,
    required this.uploading,
    required this.fileName,
    required this.onTap,
    this.previewBytes,
    this.isPdf = false,
    this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final done = fileName != null && !uploading;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: Container(
        padding: const EdgeInsets.all(MyazaSpacing.md),
        decoration: BoxDecoration(
          color: done ? colors.primary50 : colors.background,
          border: Border.all(
            color: done ? colors.primary : colors.border,
            width: done ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(MyazaRadius.md),
        ),
        child: Row(
          children: [
            if (done)
              PoaThumb(bytes: previewBytes, isPdf: isPdf)
            else
              Icon(
                uploading ? LucideIcons.loader : LucideIcons.upload,
                color: colors.textSecondary,
              ),
            const SizedBox(width: MyazaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    uploading
                        ? 'Uploading…'
                        : done
                            ? fileName!
                            : 'Tap to upload an image or PDF',
                    style: text.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (done && typeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      typeLabel!,
                      style:
                          text.bodySmall.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (done)
              Text('Replace',
                  style: text.bodySmall.copyWith(color: colors.primary)),
          ],
        ),
      ),
    );
  }
}

/// 48×48 preview of the picked file — the image itself, or a document tile for
/// a PDF (and for an image that fails to decode, so a corrupt pick still
/// renders a row rather than a broken box).
class PoaThumb extends StatelessWidget {
  final Uint8List? bytes;
  final bool isPdf;

  const PoaThumb({super.key, required this.bytes, required this.isPdf});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final data = bytes;

    if (isPdf || data == null) {
      return Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(MyazaRadius.xs),
        ),
        child: Icon(LucideIcons.fileText, size: 22, color: colors.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(MyazaRadius.xs),
      child: Image.memory(
        data,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) =>
            const PoaThumb(bytes: null, isPdf: true),
      ),
    );
  }
}
