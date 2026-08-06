import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'country_flag.dart';

// ─── Country option tile ──────────────────────────────────────────────────────
//
// One selectable country row: a bordered card holding the country's flag, its
// name, and a trailing chevron. Mirrors the web SDK's country button
// (`rounded-xl border p-4`, 32px flag, `ChevronRight`).
//
// Shared on purpose by BOTH country-select paths — the flat list (≤5 offered
// countries) and the searchable region picker (above that). They previously
// carried separate row implementations and drifted apart visually; keeping one
// widget means a styling change lands on both at once.

class CountryOptionTile extends StatelessWidget {
  /// ISO-3166 alpha-2 code, used for the flag.
  final String code;

  /// Display name shown beside the flag.
  final String label;

  /// Highlights the row (primary border + tinted fill).
  final bool isSelected;

  final VoidCallback onTap;

  const CountryOptionTile({
    super.key,
    required this.code,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final radius = BorderRadius.circular(MyazaRadius.md);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary50 : colors.background,
        borderRadius: radius,
        border: Border.all(
          color: isSelected ? colors.primary : colors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(MyazaSpacing.md),
            child: Row(
              children: [
                MyazaCountryFlag(country: code, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: text.label.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
