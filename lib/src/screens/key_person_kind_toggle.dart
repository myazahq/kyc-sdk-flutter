import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── Person or company ───────────────────────────────────────────────────────
//
// The first question on the form, because it changes what the rest of it asks:
// a company has a registration number rather than an ID country, and no
// identity of its own to verify. Left unasked, a limited company was collected
// as a person, escalated to beneficial owner (which by definition means a
// natural person), and sent a link to take a selfie.
//
// Mirrors the web SDK's KeyPersonKindToggle and the RN SDK's 1:1.

class KeyPersonKindToggle extends StatelessWidget {
  final bool isCorporate;
  final ValueChanged<bool> onChanged;

  const KeyPersonKindToggle({
    super.key,
    required this.isCorporate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    Widget option(bool value, String label) {
      final selected = isCorporate == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(MyazaRadius.lg),
            onTap: () => onChanged(value),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MyazaRadius.lg),
                border: Border.all(
                  color: selected ? colors.primary : colors.border,
                ),
                color: selected
                    ? colors.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: Text(
                label,
                style: text.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Who is this?', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        Row(children: [
          option(false, 'A person'),
          const SizedBox(width: MyazaSpacing.sm),
          option(true, 'A company'),
        ]),
      ],
    );
  }
}
