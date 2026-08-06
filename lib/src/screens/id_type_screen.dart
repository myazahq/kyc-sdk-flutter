import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/step_order.dart';
import '../widgets/myaza_pulse_loader.dart';

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

    // The server's granted list is authoritative — every offered ID is resolved
    // through [resolveIdTypeDefinition] so Global-Document IDs (no curated
    // entry) still render from the server row's metadata. The consumer's
    // `idTypes` prop, when set, narrows the offering by key. While config is
    // loading we render a placeholder; on error we fall back to the curated
    // list for the country (server still 403s anything actually disabled).
    final serverConfig = state.serverConfig;
    final country = effectiveCountry(config, state);
    // In a multi-region flow the picked country's own idTypes narrow the list;
    // otherwise the top-level `idTypes` prop applies. Null/empty = all granted.
    final propKeys = _countryIdTypeFilter(config, country) ?? config.idTypes;
    bool allowed(String key) =>
        propKeys == null || propKeys.isEmpty || propKeys.contains(key);

    final available = switch (serverConfig.status) {
      ServerConfigStatus.ready => [
          for (final row in serverConfig.idTypes)
            if (row.country == country && allowed(row.idType))
              resolveIdTypeDefinition(
                country,
                row.idType,
                label: row.label,
                requiresDocumentCapture: row.requiresDocumentCapture,
                scanSides: row.scanSides,
                supportsNfc: row.supportsNfc,
              ),
        ],
      ServerConfigStatus.error => curatedIdTypesForCountry(country)
          .where((c) => allowed(c.key))
          .toList(),
      ServerConfigStatus.loading => const <IdTypeConfig>[],
    };

    if (serverConfig.status == ServerConfigStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MyazaSpacing.xl),
        child: Center(child: MyazaPulseLoader()),
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
          final isSelected = state.selectedIdType?.key == idTypeConfig.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
            child: _IdTypeCard(
              config: idTypeConfig,
              isSelected: isSelected,
              // Picking an ID type ADVANCES — there is no Continue button. It's
              // a single-select list with nothing else on the step to confirm,
              // so a second tap only restates a decision already made. It also
              // matches country-select, which advances on tap: one list
              // advancing and the next not was the inconsistency worth
              // removing. A mis-tap costs one Back.
              onTap: () {
                notifier.setIdType(idTypeConfig);
                notifier.nextStep();
              },
            ),
          );
        }),
      ],
    );
  }
}

/// The per-country ID-type filter for a multi-region flow: the picked country's
/// `idTypes` from the `countries` list. Null for single-country flows (the
/// top-level `idTypes` prop then applies).
List<String>? _countryIdTypeFilter(MyazaKYCConfig config, String country) {
  final countries = config.countries;
  if (countries == null || countries.length <= 1) return null;
  for (final opt in countries) {
    if (opt.country.toUpperCase() == country.toUpperCase()) return opt.idTypes;
  }
  return null;
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

  // Same lucide icons as the web SDK's IdTypeStep (ID_TYPE_ICONS). Keyed by the
  // server ID key so Global-Document IDs get a sensible default icon.
  static IconData _iconFor(String key) => switch (key) {
        'bvn' || 'bvn-premium' => LucideIcons.landmark, // Bank Verification
        'tax-id'               => LucideIcons.receiptText, // Tax ID (NIN-keyed)
        'nin' || 'vnin'        => LucideIcons.fingerprint,
        'passport'             => LucideIcons.bookUser,
        'drivers-license'      => LucideIcons.idCard,
        'pvc' || 'voters'      => LucideIcons.contact, // Voter's Card
        _                      => LucideIcons.idCard,
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
                    _iconFor(config.key),
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

                // ── Forward chevron ──────────────────────────────────────────
                // Tapping a row ADVANCES immediately (no Continue button), so
                // the affordance is a "go to next step" chevron — not a radio,
                // which would imply a select-then-confirm the flow doesn't have.
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: isSelected ? colors.primary : colors.gray400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
