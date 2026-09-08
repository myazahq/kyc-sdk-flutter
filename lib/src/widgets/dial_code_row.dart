import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'country_flag.dart';
import 'geo_badge.dart';

// ─── One country in the dial-code sheet ──────────────────────────────────────
//
// Extracted from dial_code_picker.dart (200-line rule) and shared by the
// pinned geo row and the alphabetical ones, so the two cannot drift apart:
// they are the same control in two positions, and the pinned one only differs
// by carrying a tag and a hairline beneath it. Mirrors the RN DialCodeRow.

class DialCodeRow extends StatelessWidget {
  final String iso;
  final String name;

  /// The dialling code without its '+'; empty hides the trailing column.
  final String dial;
  final bool isSelected;

  /// Tags the pinned geo row ("Your location").
  final String? badge;
  final VoidCallback onTap;

  const DialCodeRow({
    super.key,
    required this.iso,
    required this.name,
    required this.dial,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Material(
      color: isSelected ? colors.primary50 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MyazaSpacing.md,
            vertical: 12,
          ),
          child: Row(
            children: [
              MyazaCountryFlag(country: iso, size: 28),
              const SizedBox(width: MyazaSpacing.md),
              Expanded(
                // Full body size in the foreground colour: the name IS the
                // row, not its caption.
                child: Text(name, style: text.body.copyWith(color: colors.textDark)),
              ),
              if (badge != null) ...[
                GeoBadge(label: badge!),
                const SizedBox(width: MyazaSpacing.sm),
              ],
              if (dial.isNotEmpty)
                Text('+$dial',
                    style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A region label between grouped rows — the country-select step's header
/// (uppercase, tracked out), so the two pickers read as one control.
class DialCodeRegionHeader extends StatelessWidget {
  final String region;
  const DialCodeRegionHeader({super.key, required this.region});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MyazaSpacing.md,
        MyazaSpacing.md,
        MyazaSpacing.md,
        MyazaSpacing.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          region.toUpperCase(),
          style: text.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The hairline under the pinned row, separating it from the alphabet.
class DialCodeDivider extends StatelessWidget {
  const DialCodeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: MyazaSpacing.sm,
      thickness: 0.5,
      indent: MyazaSpacing.md,
      endIndent: MyazaSpacing.md,
      color: context.myazaColors.border,
    );
  }
}
