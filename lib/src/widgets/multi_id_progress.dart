import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/id_types.dart';
import '../config/multi_id.dart';
import '../providers/kyc_provider.dart';
import '../config/theme.dart';

/// The multi-ID run's position strip: one chip per check, filling in with the
/// picked ID's name as each check commits, the current one highlighted.
///
/// A PORT of the web SDK's MultiIdProgress. Rendered above the picker, the
/// evidence steps and liveness so a reader always knows which of the run's IDs
/// the screen is about and how many remain — without it a three-ID run is
/// three visits to the same-looking screen with nothing saying which is which.
class MultiIdProgress extends ConsumerWidget {
  const MultiIdProgress({super.key, required this.plan});

  final MultiIdPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.myazaColors;
    final state = ref.watch(kYCNotifierProvider);
    final slots = state.multiIdSlots;

    String labelFor(String idType) {
      final row = state.serverConfig.idTypes
          .where((r) => r.idType == idType)
          .firstOrNull;
      return resolveIdTypeDefinition(
        state.selectedCountry ?? '',
        idType,
        label: row?.label,
        requiresDocumentCapture: row?.requiresDocumentCapture,
        scanSides: row?.scanSides,
        supportsNfc: row?.supportsNfc,
      ).label;
    }

    return Semantics(
      label: 'ID ${(plan.index + 1).clamp(1, plan.count)} of ${plan.count}',
      child: Container(
        margin: const EdgeInsets.only(bottom: MyazaSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: MyazaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < plan.count; i++) ...[
              if (i > 0)
                Container(
                  width: 16,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm),
                  color: (i < slots.length || i == plan.index)
                      ? colors.primary.withValues(alpha: 0.5)
                      : colors.border,
                ),
              _Chip(
                index: i,
                committed: i < slots.length,
                active: i == plan.index,
                colors: colors,
              ),
              const SizedBox(width: MyazaSpacing.sm),
              Flexible(
                child: Text(
                  i < slots.length ? labelFor(slots[i].idType) : 'ID ${i + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MyazaTypography.bodySmall.copyWith(
                    color: i == plan.index
                        ? colors.textDark
                        : colors.textMuted,
                    fontWeight:
                        i == plan.index ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.index,
    required this.committed,
    required this.active,
    required this.colors,
  });

  final int index;
  final bool committed;
  final bool active;
  final MyazaColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: committed ? colors.primary : Colors.transparent,
          border: committed
              ? null
              : Border.all(
                  color: active ? colors.primary : colors.border,
                  width: active ? 2 : 1,
                ),
        ),
        child: committed
            ? Icon(LucideIcons.check, size: 12, color: colors.onPrimary)
            : Text(
                '${index + 1}',
                style: MyazaTypography.bodySmall.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? colors.primary : colors.textMuted,
                ),
              ),
      );
}
