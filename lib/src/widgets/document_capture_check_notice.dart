import 'package:flutter/material.dart';

import '../config/document_capture_check.dart';
import '../config/theme.dart';
import 'myaza_button.dart';
import 'icons/icons.dart';

// ─── "Check your photos", on the document review ──────────────────────────────
//
// Takes Continue's place in the review footer when the server's capture check
// could not read a side (see config/document_capture_check.dart): one retake per
// side at fault, then "Continue anyway", because a detector can miss and this
// must never be a dead end.
//
// Shaped like MyazaAlert's warning, but inked for contrast. Bright amber text on
// the pale amber ground measures about 1.5:1, and these lines are instructions
// the applicant has to act on, so the light ground takes a dark amber instead.
// The dark ground already clears AA with the bright amber.

const kCaptureCheckNoticeKey = ValueKey('kyc.capture-check.notice');

/// Amber-800: the ink the upload retry line on this screen already uses.
const Color _kInkOnLightGround = Color(0xFF92400E);

/// The notice's text and icon colour. Read off the ground it sits on rather
/// than the theme's brightness, so it follows whichever scheme is painted.
Color captureNoticeInk(MyazaColorScheme colors) =>
    colors.warningBg.computeLuminance() > 0.5
        ? _kInkOnLightGround
        : MyazaColors.warning;

class DocumentCaptureCheckNotice extends StatelessWidget {
  final List<CaptureProblem> problems;

  /// The photos were picked, not taken: the buttons say "Replace".
  final bool uploadOnly;

  /// Retake [side] (`front` | `back`).
  final void Function(String side) onRetake;

  /// Advance with the photos as they are.
  final VoidCallback onContinueAnyway;

  const DocumentCaptureCheckNotice({
    super.key,
    required this.problems,
    required this.uploadOnly,
    required this.onRetake,
    required this.onContinueAnyway,
  });

  @override
  Widget build(BuildContext context) {
    final sides = captureProblemSides(problems);

    Widget retake(String side, {required bool primary}) {
      final label = captureRetakeLabel(side, uploadOnly: uploadOnly);
      const icon = MyazaIcon(MyazaIcons.rotateCcw);
      // One primary action: the first retake. The rest stay secondary.
      return primary
          ? MyazaButton(
              label: label, onPressed: () => onRetake(side), leadingIcon: icon)
          : MyazaButton.outline(
              label: label, onPressed: () => onRetake(side), leadingIcon: icon);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Notice(problems: problems),
        const SizedBox(height: MyazaSpacing.md),
        // Two retakes share a row: the footer is pinned under the photos, and
        // every stacked button is height taken from them.
        if (sides.length == 1)
          retake(sides.first, primary: true)
        else if (sides.length > 1)
          Row(
            children: [
              for (var i = 0; i < sides.length; i++) ...[
                if (i > 0) const SizedBox(width: MyazaSpacing.sm),
                Expanded(child: retake(sides[i], primary: i == 0)),
              ],
            ],
          ),
        const SizedBox(height: MyazaSpacing.sm),
        MyazaButton.outline(
          label: kCaptureCheckContinueAnyway,
          onPressed: onContinueAnyway,
          leadingIcon: const MyazaIcon(MyazaIcons.arrowRight),
        ),
      ],
    );

    // A short fade so Continue turning into a notice reads as a response to
    // the tap rather than a jump. Skipped outright under reduced motion.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return KeyedSubtree(key: kCaptureCheckNoticeKey, child: content);
    }
    return TweenAnimationBuilder<double>(
      key: kCaptureCheckNoticeKey,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: content,
    );
  }
}

class _Notice extends StatelessWidget {
  final List<CaptureProblem> problems;

  const _Notice({required this.problems});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final ink = captureNoticeInk(colors);
    // The same kind on two sides is one instruction, said once.
    final lines = {for (final p in problems) captureProblemMessage(p.kind)};

    // Announced as it appears: the applicant pressed Continue and is waiting
    // to hear what happened.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.warningBg,
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
          border: Border.all(color: MyazaColors.warning.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: MyazaColors.warning),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MyazaSpacing.md,
                    vertical: MyazaSpacing.sm + 2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MyazaIcon(MyazaIcons.triangleAlert, size: 18, color: ink),
                      const SizedBox(width: MyazaSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(kCaptureCheckTitle,
                                style: text.label.copyWith(color: ink)),
                            for (final line in lines) ...[
                              const SizedBox(height: MyazaSpacing.xs),
                              Text(line,
                                  style: text.bodySmall.copyWith(color: ink)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
