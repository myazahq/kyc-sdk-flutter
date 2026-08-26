import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/myaza_input.dart';

// ─── Business-details field parts ─────────────────────────────────────────────
//
// The shared field label and the key-people contact email, split out of
// business_details_screen.dart to keep that screen readable. The company
// profile section lives in business_company_info_fields.dart.

/// A field label with an "(optional)" or "*" suffix, matching the rest of the
/// flow's label styling.
class BusinessFieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const BusinessFieldLabel({
    super.key,
    required this.label,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Text.rich(TextSpan(children: [
      TextSpan(text: label, style: text.label),
      if (required)
        TextSpan(
          text: ' *',
          style: text.label.copyWith(color: MyazaColors.error),
        )
      else
        TextSpan(
          text: ' (optional)',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
    ]));
  }
}

/// Optional contact email used to send key-people (director/owner) verification
/// invites. Shown only when the workflow emails invites for a full-KYC role.
class BusinessContactEmailField extends StatelessWidget {
  final TextEditingController controller;
  final bool valid;
  final ValueChanged<String> onChanged;

  const BusinessContactEmailField({
    super.key,
    required this.controller,
    required this.valid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BusinessFieldLabel(label: 'Contact email for owner verification'),
        const SizedBox(height: 2),
        Text(
          "We'll email this address a link for your directors and owners to "
          'verify their identity.',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: controller,
          hint: 'admin@company.com',
          keyboardType: TextInputType.emailAddress,
          errorText: valid ? null : 'Enter a valid email address.',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
