import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/dashed_border.dart';

// ─── Test-result pin (dev/sandbox only) ───────────────────────────────────────
//
// Pick the canned outcome the register check will serve. Chosen BEFORE the
// lookup runs — repeating the control afterwards would offer to change an
// answer that has already come back. Production never shows it and never
// honours a pin if one arrives. Dimensions and motion mirror the web and RN
// SDKs' Test-result control: 40px options in a 2px track, and an indicator
// that SLIDES between the two — a block that vanishes here and reappears there
// reads as two separate things blinking; moving it says the selection
// travelled, which is what actually happened.

const _outcomes = [
  (key: 'verified', label: 'Verified'),
  (key: 'not_found', label: 'Not found'),
];

class BusinessSandboxToggle extends ConsumerWidget {
  const BusinessSandboxToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final outcome = ref.watch(
          kYCNotifierProvider.select((s) => s.businessSandboxOutcome),
        ) ??
        'verified';

    return CustomPaint(
      painter: DashedRoundedBorder(color: colors.border, radius: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test result', style: text.label),
            const SizedBox(height: MyazaSpacing.sm),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(2),
              height: 40 + 2 * 2 + 2 * 1,
              // The RN toggle subtracts the track's border and padding by hand
              // before halving; here the LayoutBuilder sits INSIDE both, so
              // its constraint IS the content box and the slid indicator keeps
              // the 2px right gap for free.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final half = constraints.maxWidth / 2;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        left: outcome == 'verified' ? 0 : half,
                        top: 0,
                        bottom: 0,
                        width: half,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.textDark,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final o in _outcomes)
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => ref
                                    .read(kYCNotifierProvider.notifier)
                                    .setBusinessField('sandboxOutcome', o.key),
                                child: SizedBox(
                                  height: 40,
                                  child: Center(
                                    // Above the indicator, or the label slides
                                    // out from under it.
                                    child: Text(
                                      o.label,
                                      style: text.bodyMedium.copyWith(
                                        color: outcome == o.key
                                            ? colors.background
                                            : colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: MyazaSpacing.sm),
            Text(
              'Returned instead of calling the register.',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
