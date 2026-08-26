import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/dashed_border.dart';

// The step's non-list furniture: the guidance box above the sections and the
// total-ownership summary below them. Split from business_key_people_screen
// (200-line rule) when the flat list became sectioned.

/// A dashed guidance card, matching the web SDK's `border-dashed` hint (and the
/// RN SDK's): rounded-xl + p-4, via the shared painter.
class KeyPeopleHint extends StatelessWidget {
  const KeyPeopleHint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return CustomPaint(
      painter: DashedRoundedBorder(
        color: colors.border,
        radius: MyazaRadius.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(MyazaSpacing.md),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
        ),
        child: child,
      ),
    );
  }
}

/// A percentage as a person would write it: 60, not 60.0.
String formatPct(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);

/// Total ownership listed, shown at the DECISION point so the disabled Continue
/// button always explains itself, wherever the offending card is.
///
/// Over 100% is factually impossible, so it is caught here rather than shipped
/// into the registry cross-check as a doomed mismatch. UNDER 100% is fine: not
/// every owner has to be listed.
class KeyPeopleTotals extends StatelessWidget {
  const KeyPeopleTotals({super.key, required this.totalPct});

  final double totalPct;

  @override
  Widget build(BuildContext context) {
    if (totalPct <= 0) return const SizedBox.shrink();
    final colors = context.myazaColors;
    final text = context.myazaText;
    final over = totalPct > 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MyazaSpacing.md,
            vertical: MyazaSpacing.sm + 4,
          ),
          decoration: BoxDecoration(
            color: over ? colors.errorBg : colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(MyazaRadius.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total ownership listed',
                style: text.bodyMedium.copyWith(
                  color: over ? MyazaColors.error : colors.textSecondary,
                ),
              ),
              Text(
                '${formatPct(totalPct)}%',
                style: text.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: over ? MyazaColors.error : colors.textDark,
                ),
              ),
            ],
          ),
        ),
        if (over) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Text(
            "Together the percentages can't exceed 100%, so reduce them by "
            '${formatPct(totalPct - 100)}%.',
            style: text.bodyMedium.copyWith(color: MyazaColors.error),
          ),
        ],
      ],
    );
  }
}
