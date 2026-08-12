import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The quiet alternative to the step indicator: a single thin bar sitting ON
/// the header's bottom edge, replacing its border rather than adding a row
/// beneath it — so choosing it costs the header no height at all.
///
/// Unlike the step circles it does not say WHICH step you are on or how many
/// there are, which is the trade: it is unaffected by step count, so a 14-step
/// KYB flow draws exactly like a 4-step one. Hosts who would rather the chrome
/// said less opt in with `progressStyle: MyazaProgressStyle.bar`.
///
/// Mirrors the React Native SDK's ProgressBar.
class KycProgressBar extends StatelessWidget {
  /// 0.0–1.0 progress fraction.
  final double progress;

  /// Steps in the flow — announced, not drawn.
  final int stepCount;

  const KycProgressBar({
    super.key,
    required this.progress,
    required this.stepCount,
  });

  /// Thickness of the bar. Deliberately heavier than the 1px border it
  /// replaces: at hairline weight it reads as a rendering artefact rather than
  /// a deliberate indicator.
  static const double height = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final fraction = progress.clamp(0.0, 1.0);
    final step = (fraction * stepCount).round().clamp(1, stepCount);

    return Semantics(
      container: true,
      label: 'Step $step of $stepCount',
      value: '$step of $stepCount',
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // The track doubles as the header's bottom border, which is why the
            // header drops its own when this is shown.
            Positioned.fill(child: ColoredBox(color: colors.border)),
            // Animated so advancing a step reads as movement rather than a
            // jump — the motion IS the feedback that the step was accepted.
            // 250ms sits inside the 150–300ms micro-interaction band.
            Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: constraints.maxWidth * fraction,
                  height: height,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(height / 2),
                      bottomRight: Radius.circular(height / 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
