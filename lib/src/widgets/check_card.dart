import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── Check card ────────────────────────────────────────────────────────────────
//
// One bordered choice card with a square check, mirroring the web SDK's
// `rounded-xl border p-3` label + shadcn Checkbox and the RN OptionRow's
// `multi` variant. The questionnaire's multi-select renders one per option;
// the Proof of Address document kind lists its kinds with these too (user
// decision 2026-09-05: the options are the information, and a sheet makes the
// person open it to find out what is on offer).
//
// A bare Material CheckboxListTile was borderless and full-bleed, so the
// options read as a dense list rather than the tappable cards every other
// choice in the flow uses.

class MyazaCheckCard extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  /// A glyph between the check and the label — the check stays.
  final IconData? icon;

  /// Greyed and inert — a choice that is locked, not one that is gone.
  final bool enabled;

  const MyazaCheckCard({
    super.key,
    required this.label,
    required this.checked,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Semantics(
      checked: checked,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
          child: Container(
            padding: const EdgeInsets.all(MyazaSpacing.md - 4),
            decoration: BoxDecoration(
              color: checked ? colors.primary50 : null,
              border: Border.all(
                color: checked ? colors.primary : colors.border,
              ),
              borderRadius: BorderRadius.circular(MyazaRadius.sm),
            ),
            child: Row(
              children: [
                MyazaCheckBox(checked: checked),
                const SizedBox(width: 10),
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: checked ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(label, style: text.bodyMedium)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 20×20 square check — the web SDK's `h-5 w-5 rounded-md` checkbox.
class MyazaCheckBox extends StatelessWidget {
  final bool checked;
  const MyazaCheckBox({super.key, required this.checked});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? colors.primary : Colors.transparent,
        border: Border.all(color: checked ? colors.primary : colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: checked
          ? Icon(LucideIcons.check, size: 14, color: colors.onPrimary)
          : null,
    );
  }
}
