import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/theme.dart';
import '../../providers/kyc_provider.dart';
import '../../widgets/dashed_border.dart';

// Dev/sandbox only: the address flow's Test-result tabs — the web and RN
// SDKs' control, on the BusinessSandboxToggle's mechanics. Four equal columns
// share one sliding indicator whose FILL takes the active outcome's semantic
// colour (the dashboard's tier/verdict language). Tabs are icon-only (four
// labels never fit a phone) and the caption names the active pick. Nothing is
// SENT until the operator taps; unclicked keeps the server default, which the
// resting position mirrors. Production never shows it.

const _options = [
  (
    key: 'address_attested',
    label: 'Attested',
    icon: LucideIcons.shieldCheck,
    pill: Color(0xFF059669),
    tintLight: Color(0xFF059669),
    tintDark: Color(0xFF34D399),
  ),
  (
    key: 'address_corroborated',
    label: 'Corroborated',
    icon: LucideIcons.badgeCheck,
    pill: Color(0xFF0284C7),
    tintLight: Color(0xFF0284C7),
    tintDark: Color(0xFF38BDF8),
  ),
  (
    key: 'address_collected',
    label: 'Collected',
    icon: LucideIcons.circleDashed,
    pill: Color(0xFF475569),
    tintLight: null,
    tintDark: null,
  ),
  (
    key: 'address_mismatch',
    label: 'Mismatch',
    icon: LucideIcons.circleX,
    pill: Color(0xFFDC2626),
    tintLight: Color(0xFFDC2626),
    tintDark: Color(0xFFF87171),
  ),
];

class AddressSandboxTabs extends ConsumerWidget {
  const AddressSandboxTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(
      kYCNotifierProvider.select((s) => s.serverConfig.environment),
    );
    if (environment == 'PRODUCTION') return const SizedBox.shrink();

    final colors = context.myazaColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = context.myazaText;
    final picked = ref.watch(
      kYCNotifierProvider.select((s) => s.addressSandboxOutcome),
    );
    final shown = picked ?? 'address_attested';
    var index = _options.indexWhere((o) => o.key == shown);
    if (index < 0) index = 0;
    final active = _options[index];

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final quarter = constraints.maxWidth / _options.length;
                  return Stack(
                    children: [
                      // The indicator slides AND recolours in one motion, so
                      // Attested → Mismatch reads as one pill travelling and
                      // turning red, never two pills blinking.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        left: quarter * index,
                        top: 0,
                        bottom: 0,
                        width: quarter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: active.pill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (i, option) in _options.indexed)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == index,
                                label: option.label,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => ref
                                      .read(kYCNotifierProvider.notifier)
                                      .setAddressSandboxOutcome(option.key),
                                  child: Center(
                                    child: Icon(
                                      option.icon,
                                      size: 18,
                                      color: i == index
                                          ? Colors.white
                                          : ((isDark
                                                  ? option.tintDark
                                                  : option.tintLight) ??
                                              colors.textSecondary),
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
              '${active.label} is returned instead of judging the pin.',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
