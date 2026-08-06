import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── One captured side, and its enlarged view ─────────────────────────────────
//
// Split from document_review.dart so each file stays readable.
//
// The photo carries only LABELS — which side it is, and that tapping enlarges
// it. The actions are named buttons underneath. An icon-only control floating
// on an image reads as decoration on a phone, where there is no hover to
// reveal what it does.

class ReviewSide {
  final ValueKey<String> key;
  final String label;
  final Uint8List bytes;
  final VoidCallback? onRetake;

  const ReviewSide({
    required this.key,
    required this.label,
    required this.bytes,
    this.onRetake,
  });
}

class DocumentReviewThumb extends StatelessWidget {
  final ReviewSide side;
  final double aspect;
  final bool isBusy;
  final Widget? busyOverlay;
  final VoidCallback onZoom;

  const DocumentReviewThumb({
    super.key,
    required this.side,
    required this.aspect,
    required this.isBusy,
    required this.onZoom,
    this.busyOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          key: side.key,
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          child: Stack(
            children: [
              GestureDetector(
                onTap: onZoom,
                child: AspectRatio(
                  // The whole card stays visible at half width — a cropped
                  // thumbnail cannot be checked for legibility, which is the
                  // only reason this screen exists.
                  aspectRatio: aspect,
                  child: ColoredBox(
                    color: colors.backgroundSecondary,
                    child: Image.memory(side.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                top: 6,
                child: _Chip(child: Text(side.label, style: _chipTextStyle)),
              ),
              // Enlarging is a tap on the image, which nothing announces — so
              // the image says so itself.
              const Positioned(
                right: 6,
                bottom: 6,
                child: _Chip(
                  child: Icon(LucideIcons.maximize2,
                      size: 12, color: Colors.white),
                ),
              ),
              if (busyOverlay != null) Positioned.fill(child: busyOverlay!),
            ],
          ),
        ),
        const SizedBox(height: MyazaSpacing.xs),
        // Retake as a LABELLED control, not an icon on the photo.
        //
        // The web version hides it under the image and reveals it on hover;
        // a phone has no hover, so that became a small unlabelled circle
        // people did not read as a button. Naming it costs a few pixels and
        // is the difference between a discoverable action and a decoration.
        TextButton.icon(
          onPressed: isBusy ? null : side.onRetake,
          icon: const Icon(LucideIcons.rotateCcw, size: 14),
          label: Text('Retake', style: text.bodySmall),
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
            padding: const EdgeInsets.symmetric(vertical: 4),
            minimumSize: const Size(0, 36), // stays a comfortable tap target
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

/// Full-bleed view of one side, with retake to hand — checking a capture and
/// deciding to redo it are the same moment.
///
/// Deliberately opaque and dark. The first version tinted the theme background
/// at 97% opacity, which on the dark theme is very nearly the colour it sits
/// on: tapping a photo appeared to do nothing. An overlay has to announce
/// itself as a new layer, so this one is near-black regardless of theme, with a
/// close control big enough to find.
class DocumentReviewZoom extends StatelessWidget {
  final ReviewSide side;
  final bool isBusy;
  final VoidCallback onClose;
  final VoidCallback onRetake;

  const DocumentReviewZoom({
    super.key,
    required this.side,
    required this.isBusy,
    required this.onClose,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xF20A0A12), // ~95% opaque near-black
      child: Padding(
        padding: const EdgeInsets.all(MyazaSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Chip(child: Text(side.label, style: _chipTextStyle)),
                const Spacer(),
                // A filled circle, not a bare glyph on a dark field: the way
                // out of a full-screen view has to be obvious.
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onClose,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(LucideIcons.x, size: 20, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyazaSpacing.sm),
            Expanded(
              // Tapping the image again closes it — the same gesture that
              // opened it, which is what people try first.
              child: GestureDetector(
                onTap: onClose,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(MyazaRadius.md),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(side.bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: MyazaSpacing.sm),
            const Text(
              'Pinch to zoom in further.',
              style: _hintTextStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyazaSpacing.sm),
            FilledButton.icon(
              onPressed: isBusy ? null : onRetake,
              icon: const Icon(LucideIcons.rotateCcw, size: 16),
              label: Text('Retake ${side.label.toLowerCase()}'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _hintTextStyle = TextStyle(fontSize: 12, color: Color(0x99FFFFFF));

const _chipTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: Colors.white,
);

/// A small dark label over the photo. Non-interactive by design — the actions
/// on this screen are named buttons, not icons floating on an image.
class _Chip extends StatelessWidget {
  final Widget child;

  const _Chip({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: child,
      );
}
