import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../widgets/country_flag.dart';

export 'proof_of_address_uploaded_row.dart';

// ─── Proof of Address — upload states ─────────────────────────────────────────
//
// Two states, mirroring the web SDK's ProofOfAddressStep:
//
//   empty    a DASHED drop zone that NAMES the document being asked for
//            ("Upload your utility bill") plus what's accepted (the shared
//            upload hint). A generic "tap to upload" hid which of the offered
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

  /// The country the document is for — the flag before the call to action
  /// (user decision 2026-09-05). Null when the flow does not know it yet (the
  /// address scope before a pick): nothing is invented.
  final String? country;

  final VoidCallback? onTap;

  const PoaDropzone({
    super.key,
    required this.uploading,
    required this.typeLabel,
    this.country,
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (country != null) ...[
                    MyazaCountryFlag(country: country, size: 18),
                    const SizedBox(width: MyazaSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      uploading
                          ? 'Uploading…'
                          : 'Upload your ${typeLabel.toLowerCase()}',
                      style: text.label,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                kUploadHint,
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
