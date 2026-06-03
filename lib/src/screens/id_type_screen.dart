import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/id_types.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../widgets/myaza_button.dart';

// ─── ID type selection screen ─────────────────────────────────────────────────

class IdTypeScreen extends ConsumerWidget {
  const IdTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config   = ref.watch(kycConfigProvider);
    final state    = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final colors   = context.myazaColors;
    final text     = context.myazaText;

    // Start from the consumer's `idTypes` prop (if any), then intersect with
    // the server-driven access list. Server is authoritative — IDs not
    // granted are stripped silently. While the config is loading we render a
    // placeholder. On error we fall back to the prop list (server still 403s
    // anything actually disabled, so this is at worst as restrictive as the
    // server).
    final propList = getIdTypesForCountry(
      config.country,
      allowedTypes: config.idTypes,
    );
    final serverConfig = state.serverConfig;
    final grantedKeys = <String>{
      for (final row in serverConfig.idTypes)
        if (row.country == config.country.name) row.idType,
    };
    final available = switch (serverConfig.status) {
      ServerConfigStatus.ready =>
        propList.where((t) => grantedKeys.contains(t.key)).toList(),
      ServerConfigStatus.error => propList,
      ServerConfigStatus.loading => const <IdTypeConfig>[],
    };

    if (serverConfig.status == ServerConfigStatus.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: MyazaSpacing.md),
              Text(
                'Loading available ID types…',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (serverConfig.status == ServerConfigStatus.ready && available.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(MyazaSpacing.md),
        child: Container(
          padding: const EdgeInsets.all(MyazaSpacing.md),
          decoration: BoxDecoration(
            color: colors.errorBg,
            borderRadius: BorderRadius.circular(MyazaRadius.md),
            border: Border.all(color: MyazaColors.error.withValues(alpha: 0.3)),
          ),
          child: Text(
            'No ID types are enabled for your organization. Contact your administrator to request access.',
            style: text.bodyMedium.copyWith(color: MyazaColors.error),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ID type cards ────────────────────────────────────────────────────
        ...available.map((idTypeConfig) {
          final isSelected = state.selectedIdType == idTypeConfig.idType;
          return Padding(
            padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
            child: _IdTypeCard(
              config: idTypeConfig,
              isSelected: isSelected,
              onTap: () => notifier.setIdType(idTypeConfig.idType),
            ),
          );
        }),

        const SizedBox(height: MyazaSpacing.lg),

        // ── Continue ─────────────────────────────────────────────────────────
        MyazaButton(
          label: 'Continue',
          onPressed: state.selectedIdType != null ? notifier.nextStep : null,
        ),
      ],
    );
  }
}

// ─── Individual ID type card ──────────────────────────────────────────────────

class _IdTypeCard extends StatelessWidget {
  final IdTypeConfig config;
  final bool isSelected;
  final VoidCallback onTap;

  const _IdTypeCard({
    required this.config,
    required this.isSelected,
    required this.onTap,
  });

  // Same lucide icons as the web SDK's IdTypeStep (ID_TYPE_ICONS).
  static IconData _iconFor(IdType type) => switch (type) {
        IdType.bvn            => LucideIcons.fingerprint,
        IdType.nin            => LucideIcons.creditCard,
        IdType.vnin           => LucideIcons.creditCard,
        IdType.passport       => LucideIcons.globe,
        IdType.driversLicense => LucideIcons.car,
        IdType.pvc            => LucideIcons.vote,
        IdType.ghanaCard      => LucideIcons.creditCard,
        IdType.voters         => LucideIcons.vote,
        IdType.ssnit          => LucideIcons.fileText,
        IdType.nationalId     => LucideIcons.creditCard,
        IdType.cni            => LucideIcons.creditCard,
        IdType.residenceCard  => LucideIcons.fileText,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;

    final borderColor = isSelected ? colors.primary : colors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary50 : colors.background,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        border: Border.all(
          color: borderColor,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          splashColor: colors.primary.withValues(alpha: 0.06),
          highlightColor: colors.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MyazaSpacing.md,
              vertical: MyazaSpacing.md,
            ),
            child: Row(
              children: [
                // ── Icon container ───────────────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected ? colors.primary100 : colors.primary50,
                    borderRadius: BorderRadius.circular(MyazaRadius.sm),
                  ),
                  child: Icon(
                    _iconFor(config.idType),
                    size: 22,
                    color: isSelected ? colors.primary : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: MyazaSpacing.md),

                // ── Label ────────────────────────────────────────────────────
                Expanded(
                  child: Text(
                    config.label,
                    style: text.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(width: MyazaSpacing.md),

                // ── Radio circle ─────────────────────────────────────────────
                _RadioCircle(isSelected: isSelected, colors: colors),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Radio circle ─────────────────────────────────────────────────────────────

class _RadioCircle extends StatelessWidget {
  final bool isSelected;
  final MyazaColorScheme colors;

  const _RadioCircle({required this.isSelected, required this.colors});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(
          color: isSelected ? colors.primary : colors.gray300,
          width: 1.5,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary,
                ),
              ),
            )
          : null,
    );
  }
}
