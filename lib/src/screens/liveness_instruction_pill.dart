import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';
import 'liveness_frosted.dart';

/// What the line over the camera is saying, which decides its mark.
enum LivenessInstructionTone {
  /// What to do next.
  prompt,

  /// Something is in the way: no face, too close, the wrong gesture.
  warning,

  /// A step has landed, or the photo is taken.
  done,
}

/// The instruction over the full-screen camera.
///
/// Three things the plain line in the sheet did not need:
///
///  - It is read out. The person is looking at their own face, and somebody
///    using a screen reader cannot see the words at all, so every change is
///    announced (a live region).
///  - A warning carries a mark as well as its red, and a finished step a tick
///    as well as its green: the colour is never the only signal.
///  - The words change in place. The pill keeps its position and eases to its
///    new width while one line fades into the next, where it used to jump.
class LivenessInstructionPill extends StatelessWidget {
  const LivenessInstructionPill({
    super.key,
    required this.text,
    this.tone = LivenessInstructionTone.prompt,
    this.leading,
  });

  final String text;
  final LivenessInstructionTone tone;

  /// The gesture's picture, on a phone too short to show it above the pill.
  /// Shown for a prompt only: a warning's mark takes its place.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final still = MediaQuery.disableAnimationsOf(context);
    final duration =
        still ? Duration.zero : const Duration(milliseconds: 220);

    final Widget? mark = switch (tone) {
      LivenessInstructionTone.warning => const MyazaIcon(
          MyazaIcons.triangleAlert,
          size: 20,
          color: MyazaColors.error,
        ),
      LivenessInstructionTone.done => const MyazaIcon(
          MyazaIcons.circleCheck,
          size: 20,
          color: MyazaColors.success,
        ),
      LivenessInstructionTone.prompt => leading,
    };

    // The green of a finished step does not reach 4.5:1 on a light surface,
    // so the tick carries it and the words stay the text colour.
    final textColor = tone == LivenessInstructionTone.warning
        ? MyazaColors.error
        : colors.textDark;

    return Center(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: text,
        child: ExcludeSemantics(
          child: LivenessFrostedPill(
            opacity: 0.92,
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Row(
                  key: ValueKey('${tone.name}:${leading != null}:$text'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mark != null) ...[
                      mark,
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        text,
                        style: context.myazaText.heading3
                            .copyWith(color: textColor),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How far through the gestures the person is, under the window: what the row
/// of dots says in the sheet, in words.
class LivenessStepCount extends StatelessWidget {
  const LivenessStepCount({
    super.key,
    required this.step,
    required this.total,
  });

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Center(
      child: LivenessFrostedPill(
        child: Text(
          'Step $step of $total',
          style: context.myazaText.bodySmall.copyWith(
            color: colors.textDark,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
