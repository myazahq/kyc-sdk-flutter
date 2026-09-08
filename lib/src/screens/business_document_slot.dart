import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../widgets/dashed_border.dart';

// ─── One business-document upload slot ────────────────────────────────────────
//
// A tap target per configured document type: empty it invites a pick, filled it
// shows a thumbnail of what was actually picked plus a remove button. Showing
// the file back matters — it's the only way a user catches "wrong photo from
// the camera roll" before submitting.
//
// PDFs get a document tile instead of a thumbnail (the SDK ships no PDF
// renderer). Mirrors the web SDK's BusinessDocumentSlot.

class BusinessDocumentSlot extends StatelessWidget {
  final String label;
  final bool required;
  final String? fileName;

  /// Bytes of the picked file, kept for the thumbnail. Null for PDFs or when
  /// nothing has been picked yet.
  final Uint8List? previewBytes;

  /// Local temp path of the picked image — the record-persisted fallback that
  /// survives leaving the step after [previewBytes] (screen state) is gone.
  final String? previewPath;
  final bool isPdf;

  final bool uploading;
  final String? error;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const BusinessDocumentSlot({
    super.key,
    required this.label,
    required this.required,
    required this.fileName,
    required this.uploading,
    this.previewBytes,
    this.previewPath,
    this.isPdf = false,
    this.error,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final done = fileName != null && !uploading;
    final hasError = error != null;

    // Mirrors the web SDK's BusinessDocumentSlot exactly: EMPTY is a 2px
    // DASHED rounded-xl tap target (upload glyph · label with a red * ·
    // the shared upload hint); FILLED is a solid muted card with the
    // file's preview/name, the slot label beneath, Replace, and remove.
    final Widget inner;
    if (done) {
      inner = Container(
        padding: const EdgeInsets.all(MyazaSpacing.md),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          border: Border.all(
            color: hasError ? MyazaColors.error : colors.border,
          ),
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
        ),
        child: Row(
          children: [
            _Leading(
              done: done,
              uploading: uploading,
              previewBytes: previewBytes,
              previewPath: previewPath,
              isPdf: isPdf,
            ),
            const SizedBox(width: MyazaSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName!,
                    style: text.label.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style:
                        text.bodySmall.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Breathing room so a truncated file name never crowds the CTA.
            const SizedBox(width: MyazaSpacing.sm + 4),
            // Whole-row tap re-picks too; the explicit label matches web.
            Text(
              'Replace',
              style: text.bodySmall.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove $label',
                icon: Icon(LucideIcons.x,
                    size: 18, color: colors.textSecondary),
              ),
          ],
        ),
      );
    } else {
      inner = CustomPaint(
        painter: DashedRoundedBorder(
          color: hasError ? MyazaColors.error : colors.border,
          radius: MyazaRadius.sm,
          strokeWidth: 2,
        ),
        child: Container(
          padding: const EdgeInsets.all(MyazaSpacing.md),
          child: Row(
            children: [
              if (uploading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              else
                Icon(LucideIcons.upload, size: 20, color: colors.textMuted),
              const SizedBox(width: MyazaSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: label,
                          style: text.label
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (required)
                          TextSpan(
                            text: ' *',
                            style: text.label
                                .copyWith(color: MyazaColors.error),
                          ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      uploading ? 'Uploading…' : kUploadHint,
                      style: text.bodySmall
                          .copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: MyazaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: uploading ? null : onTap,
            borderRadius: BorderRadius.circular(MyazaRadius.sm),
            child: inner,
          ),
          if (hasError) ...[
            const SizedBox(height: MyazaSpacing.xs),
            Text(error!,
                style: text.bodySmall.copyWith(color: MyazaColors.error)),
          ],
        ],
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final bool done;
  final bool uploading;
  final Uint8List? previewBytes;
  final String? previewPath;
  final bool isPdf;

  const _Leading({
    required this.done,
    required this.uploading,
    required this.previewBytes,
    required this.previewPath,
    required this.isPdf,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // Web parity: UploadedFileThumb is h-12 w-12 rounded-lg (48 / radius 8).
    const size = 48.0;

    if (uploading) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (done && previewBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(MyazaRadius.xs),
        child: Image.memory(
          previewBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A picker can hand back bytes Flutter can't decode (HEIC on some
          // devices); fall back to the tile rather than throwing in build.
          errorBuilder: (_, __, ___) =>
              _Tile(icon: LucideIcons.fileText, colors: colors),
        ),
      );
    }

    // Screen-state bytes are gone (the step was left and re-entered) — the
    // record-persisted temp path still renders the same thumbnail.
    if (done && previewPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(MyazaRadius.xs),
        child: Image.file(
          File(previewPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // The OS may have purged the temp file — degrade to the check tile.
          errorBuilder: (_, __, ___) =>
              _Tile(icon: LucideIcons.check, colors: colors, tinted: true),
        ),
      );
    }

    return _Tile(
      icon: done
          ? (isPdf ? LucideIcons.fileText : LucideIcons.check)
          : LucideIcons.upload,
      colors: colors,
      tinted: done,
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final MyazaColorScheme colors;
  final bool tinted;

  const _Tile({required this.icon, required this.colors, this.tinted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tinted ? colors.primary100 : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Icon(icon,
          size: 20, color: tinted ? colors.primary : colors.textSecondary),
    );
  }
}
