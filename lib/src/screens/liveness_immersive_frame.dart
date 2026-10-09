import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'liveness_blur_scope.dart';
import 'liveness_cutout.dart';

// ─── The full-screen liveness camera ─────────────────────────────────────────
//
// The camera owns the display, as it does for document capture: the feed runs
// edge to edge, and everything except a tall, round-ended window for the face
// is blurred behind a tint. The face is the one sharp thing on the screen, so
// there is nothing else to look at.
//
// The tint is the flow's own BACKGROUND colour, so the instruction and the
// errors keep the colours they have always had and stay readable.
//
// The window is centred across, and on a short screen sits a little below the
// centre so the gesture picture above it keeps a readable size
// (livenessWindowDrop). The "centre your face" guidance is judged against the
// window wherever it sits (faceWindowFor is given the same drop).
// The window's size is worked out HERE, from the box this frame is actually
// given, and handed to whoever draws on it or judges the face against it: a
// second measurement taken from the screen disagrees with this one whenever
// the SDK does not have the whole display (split view, a host that insets it).

/// How much of the tint covers the blurred feed in a well-lit room. A real
/// blur under a thin tint: the blur moves the eye to the window, the tint only
/// evens the background out.
const double kLivenessTint = 0.16;

/// The tint in a dark room. The step is lit so the SCREEN lights the face,
/// and a thin tint over a dark room is a dark screen: this hands most of the
/// display back to the light background.
const double kLivenessDimRoomTint = 0.66;

/// The tint when there is no blur under it (a slow phone, or high contrast):
/// it then has to do the blur's job of quietening the room.
const double kLivenessFlatTint = 0.74;

const double _kBlurSigma = 11;

/// The back and close buttons the shell draws over the frame: the gap above
/// them, and the height they take with the gaps around them.
const double _kControlsTopGap = 8;
const double _kControlsBand = 56;

class LivenessImmersiveFrame extends StatelessWidget {
  const LivenessImmersiveFrame({
    super.key,
    required this.preview,
    required this.cutout,
    required this.above,
    required this.below,
    this.footer,
    this.footerReserve = 32,
    this.tint = kLivenessTint,
    this.onSize,
  });

  /// The live camera, cover-fit to the whole frame.
  final Widget preview;

  /// What is drawn ON the window: its border, the progress ring, the marks.
  /// Given the window's size; its own centre is placed on the window's.
  final Widget Function(Size window) cutout;

  /// The instruction, resting just above the window, and over it whatever is
  /// narrow enough to stand BETWEEN the back and close buttons (the gesture
  /// picture). Given the height there is under those buttons (`room`) and the
  /// height up to their top (`reach`): what is wide keeps to the first, what
  /// is narrow and centred may use the second.
  final Widget Function(double room, double reach) above;

  /// What starts just below the window: the step count, or the retry.
  final Widget below;

  /// What rests on the bottom edge: one quiet line, or the review's buttons.
  final Widget? footer;

  /// The height [footer] needs, kept clear of [below].
  final double footerReserve;

  /// How much of the background colour covers the feed, 0 to 1.
  final double tint;

  /// The size of the box the camera is cover-fit to, whenever it changes.
  final ValueChanged<Size>? onSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final blurs = LivenessBlurScope.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    // Read from the VIEW: the flow's sheet strips the inherited padding (see
    // DocumentViewfinder for the long version).
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        onSize?.call(size);
        final cutoutSize = livenessCutout(size);
        final centre = size.center(Offset.zero) +
            Offset(0, livenessWindowDrop(size, cutoutSize, insets.top));
        final half = cutoutSize.height / 2;
        final window = Rect.fromCenter(
          center: centre,
          width: cutoutSize.width,
          height: cutoutSize.height,
        );
        // The block starts level with the top of the back and close buttons
        // the shell draws, not under them: they sit at the sides, and the
        // middle of that band is free.
        final aboveTop = insets.top + _kControlsTopGap;
        final aboveBottom = centre.dy - half - 20;
        final room =
            math.max(0.0, aboveBottom - insets.top - _kControlsBand);
        final reach = math.max(0.0, aboveBottom - aboveTop);
        final contentWidth =
            math.max(0.0, size.width - MyazaSpacing.lg * 2);
        return Stack(
          fit: StackFit.expand,
          children: [
            preview,
            // One surface over everything except the window.
            ClipPath(
              clipper: _OutsideWindow(window),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  end: blurs ? tint : math.max(tint, kLivenessFlatTint),
                ),
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, opacity, _) {
                  final fill = ColoredBox(
                    color: colors.background.withValues(alpha: opacity),
                  );
                  if (!blurs) return fill;
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _kBlurSigma,
                      sigmaY: _kBlurSigma,
                    ),
                    child: fill,
                  );
                },
              ),
            ),
            Positioned.fromRect(rect: window, child: cutout(cutoutSize)),
            Positioned(
              left: MyazaSpacing.lg,
              right: MyazaSpacing.lg,
              top: aboveTop,
              // On a very short phone the words keep their height under the
              // buttons and run over the window's top edge instead.
              height: livenessAboveHeight(room) +
                  _kControlsBand -
                  _kControlsTopGap,
              // Scaled down as a last resort (a very short phone, very large
              // text) so the words never slide off the top.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: above(room, reach),
                ),
              ),
            ),
            Positioned(
              left: MyazaSpacing.lg,
              right: MyazaSpacing.lg,
              top: centre.dy + half + 24,
              bottom:
                  insets.bottom + (footer == null ? 12 : footerReserve + 24),
              child: SingleChildScrollView(child: below),
            ),
            if (footer != null)
              Positioned(
                left: MyazaSpacing.lg,
                right: MyazaSpacing.lg,
                bottom: insets.bottom + 12,
                child: Center(child: footer),
              ),
          ],
        );
      },
    );
  }
}

class _OutsideWindow extends CustomClipper<Path> {
  const _OutsideWindow(this.window);

  final Rect window;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(RRect.fromRectAndRadius(
      window,
      Radius.circular(window.shortestSide / 2),
    ));

  @override
  bool shouldReclip(_OutsideWindow old) => old.window != window;
}
