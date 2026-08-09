import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── Proof of Address — upload states ─────────────────────────────────────────
//
// Two states, mirroring the web SDK's ProofOfAddressStep:
//
//   empty    a DASHED drop zone that NAMES the document being asked for
//            ("Upload your utility bill") plus what's accepted ("Photo or PDF,
//            up to 20MB"). A generic "tap to upload" hid which of the offered
//            document kinds the user was actually supposed to supply.
//   uploaded a solid row: thumbnail of the picked file, its name, the document
//            kind underneath, and an X to remove it.
//
// The preview renders the in-memory bytes from the picker (no server round
// trip); PDFs get a document tile, since the SDK ships no PDF renderer.

/// The empty / uploading state — a dashed drop zone.
class PoaDropzone extends StatelessWidget {
  final bool uploading;

  /// The document kind being asked for, e.g. "Utility bill". Lower-cased into
  /// the call to action so it reads "Upload your utility bill".
  final String typeLabel;

  final VoidCallback? onTap;

  const PoaDropzone({
    super.key,
    required this.uploading,
    required this.typeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: CustomPaint(
        painter: DashedRRectPainter(
          color: colors.border,
          radius: MyazaRadius.md,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: MyazaSpacing.xl,
            horizontal: MyazaSpacing.lg,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (uploading)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                )
              else
                Icon(LucideIcons.upload, size: 30, color: colors.textSecondary),
              const SizedBox(height: MyazaSpacing.sm),
              Text(
                uploading
                    ? 'Uploading…'
                    : 'Upload your ${typeLabel.toLowerCase()}',
                style: text.label,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'Photo or PDF, up to 20MB',
                style: text.bodySmall.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The uploaded state — thumbnail, file name, document kind, and a remove (X).
class PoaUploadedRow extends StatelessWidget {
  final String fileName;
  final String typeLabel;
  final Uint8List? previewBytes;
  final bool isPdf;
  final VoidCallback? onRemove;

  const PoaUploadedRow({
    super.key,
    required this.fileName,
    required this.typeLabel,
    required this.previewBytes,
    required this.isPdf,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Row(
        children: [
          PoaThumb(bytes: previewBytes, isPdf: isPdf),
          const SizedBox(width: MyazaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: text.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  typeLabel,
                  style: text.bodySmall.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove document',
              icon: Icon(LucideIcons.x, size: 18, color: colors.textSecondary),
            ),
        ],
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

/// Paints a dashed rounded-rectangle outline. Flutter has no dashed `Border`,
/// and the dashes are what mark the zone as a drop target rather than a filled
/// field — so it's worth the painter.
class DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  const DashedRRectPainter({
    required this.color,
    required this.radius,
    this.dashLength = 6,
    this.gapLength = 4,
    this.strokeWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      // Inset by half the stroke so the dashes aren't clipped at the edges.
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gapLength != gapLength ||
      oldDelegate.strokeWidth != strokeWidth;
}
