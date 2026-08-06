import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import 'document_review_side.dart';

// ─── Document review ──────────────────────────────────────────────────────────
//
// What the user sees once their document is captured.
//
// The two-sided version used to stack the sides full-width with a retake button
// under each, which on a phone pushed the back image AND the Continue button
// below the fold — people reported not realising there was anything left to do.
// A review screen whose primary action you have to discover by scrolling is a
// dead end, so the layout is:
//
//   • both sides SIDE BY SIDE at every size, so "both captured" reads at a
//     glance instead of by scrolling;
//   • retake as an overlay on each thumbnail, which removes the two full-width
//     buttons that cost the most vertical space;
//   • the action bar PINNED to the bottom, so Continue is visible however tall
//     the content gets;
//   • tap a thumbnail to enlarge it — side by side means smaller, and checking
//     the capture is legible is the entire point of this screen.
//
// Mirrors the web SDK's DocumentReview so the two behave the same.

const kDocumentReviewFrontKey = ValueKey('kyc.review.front');
const kDocumentReviewBackKey = ValueKey('kyc.review.back');
const kDocumentReviewFooterKey = ValueKey('kyc.review.footer');
const kDocumentReviewZoomKey = ValueKey('kyc.review.zoom');

class DocumentReview extends StatefulWidget {
  final Uint8List front;
  final Uint8List? back;

  /// Document aspect, so a half-width thumbnail still shows the whole card.
  final double aspect;

  /// Uploading — dims the thumbnails and disables retake.
  final bool isBusy;

  final VoidCallback? onRetakeFront;
  final VoidCallback? onRetakeBack;

  /// Painted over each thumbnail while busy (the upload loader).
  final Widget? busyOverlay;

  /// Errors, retry notices and the Continue button — pinned below the images.
  final Widget footer;

  const DocumentReview({
    super.key,
    required this.front,
    this.back,
    required this.aspect,
    required this.isBusy,
    required this.footer,
    this.onRetakeFront,
    this.onRetakeBack,
    this.busyOverlay,
  });

  @override
  State<DocumentReview> createState() => _DocumentReviewState();
}

class _DocumentReviewState extends State<DocumentReview> {
  ReviewSide? _zoomed;

  List<ReviewSide> get _sides => [
        ReviewSide(
          key: kDocumentReviewFrontKey,
          label: 'Front',
          bytes: widget.front,
          onRetake: widget.onRetakeFront,
        ),
        if (widget.back != null)
          ReviewSide(
            key: kDocumentReviewBackKey,
            label: 'Back',
            bytes: widget.back!,
            onRetake: widget.onRetakeBack,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final sides = _sides;
    final twoSided = sides.length > 1;
    final colors = context.myazaColors;
    final text = context.myazaText;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Says the capture is COMPLETE — the thing users were scrolling to
        // find out.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: MyazaColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.check,
                  size: 13, color: MyazaColors.success),
            ),
            const SizedBox(width: MyazaSpacing.xs),
            Text(
              twoSided ? 'Both sides captured' : 'Photo captured',
              style: text.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: MyazaSpacing.md),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Top-aligned: the images are what the user checks first, so
              // they sit where the eye lands rather than floating in the
              // middle of the screen. Scrolls when they do not fit.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < sides.length; i++) ...[
                      if (i > 0) const SizedBox(width: MyazaSpacing.sm),
                      Expanded(
                        child: DocumentReviewThumb(
                          side: sides[i],
                          aspect: widget.aspect,
                          isBusy: widget.isBusy,
                          busyOverlay: widget.busyOverlay,
                          onZoom: () => setState(() => _zoomed = sides[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: MyazaSpacing.xs),
                    Text(
                      'Tap a photo to see it larger.',
                      style: text.bodySmall.copyWith(color: colors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Pinned: the action can never end up below the fold — and clear of the
        // home indicator, which the sheet's full-viewport branch does NOT pad
        // for (it expects each screen to carry its own bottom inset).
        //
        // Read from the view rather than MediaQuery.of: an ancestor
        // removePadding reduces viewPadding too, so the inset would come back
        // as zero and the button would sit on the indicator.
        Padding(
          key: kDocumentReviewFooterKey,
          padding: EdgeInsets.only(
            top: MyazaSpacing.md,
            bottom: MediaQueryData.fromView(View.of(context)).viewPadding.bottom +
                MyazaSpacing.sm,
          ),
          child: widget.footer,
        ),
      ],
    );

    final zoomed = _zoomed;
    return Stack(
      children: [
        body,
        if (zoomed != null)
          Positioned.fill(
            key: kDocumentReviewZoomKey,
            // An implicit fade rather than flutter_animate: this overlay is
            // mounted and unmounted repeatedly, and the package leaves a timer
            // pending that widget tests cannot flush.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (context, t, child) =>
                  Opacity(opacity: t, child: child),
              child: DocumentReviewZoom(
                side: zoomed,
                isBusy: widget.isBusy,
                onClose: () => setState(() => _zoomed = null),
                onRetake: () {
                  final retake = zoomed.onRetake;
                  setState(() => _zoomed = null);
                  retake?.call();
                },
              ),
            ),
          ),
      ],
    );
  }
}
