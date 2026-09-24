import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../utils/map_tiles.dart' show mapSurfaceHeight;
import '../../widgets/dashed_border.dart';
import '../../widgets/myaza_button.dart';
import '../../widgets/sticky_actions.dart';
import '../../widgets/icons/icons.dart';

// ─── The entrance step's SANDBOX stand-in ────────────────────────────────────
//
// A SANDBOX mount keeps the step real users get, on a static placeholder (the
// camera steps' rule): no Google loads from a test key, the server cans the
// verdict regardless, and "Use this view" simply advances. Mirrors the web
// SDK's preview branch; the RN twin is EntranceFraming.tsx.

class AddressEntrancePlaceholder extends StatelessWidget {
  final bool hideSkip;
  final VoidCallback onSkip;
  final VoidCallback onUse;

  const AddressEntrancePlaceholder({
    super.key,
    required this.hideSkip,
    required this.onSkip,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    // Web's `rounded-xl border-2 border-dashed border-border bg-muted/40`,
    // the same box RN draws: a DASHED edge, not a solid one.
    return StickyActions(
      body: CustomPaint(
        painter: DashedRoundedBorder(
            color: colors.border, radius: MyazaRadius.sm, strokeWidth: 2),
        child: Container(
          height: mapSurfaceHeight(MediaQuery.sizeOf(context)),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(MyazaRadius.sm),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MyazaIcon(MyazaIcons.landmark,
                  size: 32, color: colors.textSecondary.withValues(alpha: 0.6)),
              const SizedBox(height: MyazaSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 288),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: MyazaSpacing.lg),
                  child: Text(
                    'Applicants pan real street imagery to frame their '
                    'entrance here. It loads only for real users.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: Row(children: [
        if (!hideSkip) ...[
          Expanded(child: MyazaButton.outline(label: 'Skip', onPressed: onSkip)),
          const SizedBox(width: MyazaSpacing.sm),
        ],
        Expanded(child: MyazaButton(label: 'Use this view', onPressed: onUse)),
      ]),
    );
  }
}
