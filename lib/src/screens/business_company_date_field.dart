import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/themed_sheet.dart';
import '../widgets/icons/icons.dart';

// ─── Date of incorporation field ─────────────────────────────────────────────
//
// A date gets the picker, not a text box — the same control the questionnaire
// uses; emits strict YYYY-MM-DD. Split from business_company_info_fields.dart
// (200-line rule).

class BusinessDateField extends StatelessWidget {
  final String? value;
  final String placeholder;
  final void Function(String iso) onChanged;

  const BusinessDateField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime.tryParse(value ?? '') ?? now;
        final picked = await showMyazaDatePicker(
          context,
          initialDate: initial,
          firstDate: DateTime(1800),
          lastDate: now,
        );
        if (picked != null) {
          onChanged(picked.toIso8601String().split('T').first);
        }
      },
      borderRadius: BorderRadius.circular(MyazaRadius.sm),
      child: Container(
        height: MyazaSizing.inputHeight,
        padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
        ),
        child: Row(
          children: [
            MyazaIcon(MyazaIcons.calendar, size: 18, color: colors.textSecondary),
            const SizedBox(width: MyazaSpacing.sm),
            Text(
              value ?? placeholder,
              style: text.body.copyWith(
                color: value == null ? colors.textMuted : colors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
