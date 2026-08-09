import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/theme.dart';
import '../widgets/myaza_input.dart';

// ─── Business-details field parts ─────────────────────────────────────────────
//
// The company-profile section and the key-people contact email, split out of
// business_details_screen.dart to keep that screen readable. Mirrors the web
// SDK's BusinessCompanyInfoFields + BusinessContactEmailField.

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

/// Company profile (address / email / phone / website) on the business-details
/// step. Each field's mode comes from the workflow config — `off` hides it,
/// `required` blocks Continue. The address is cross-checked against the
/// official registry record server-side.
class BusinessCompanyInfoFields extends StatelessWidget {
  final Map<CompanyInfoField, CompanyInfoMode> modes;
  final Map<CompanyInfoField, TextEditingController> controllers;

  /// False when the typed business email is non-empty and malformed.
  final bool emailValid;
  final ValueChanged<String> onChanged;

  const BusinessCompanyInfoFields({
    super.key,
    required this.modes,
    required this.controllers,
    required this.emailValid,
    required this.onChanged,
  });

  TextInputType _keyboardFor(CompanyInfoField field) => switch (field) {
        CompanyInfoField.email => TextInputType.emailAddress,
        CompanyInfoField.phone => TextInputType.phone,
        CompanyInfoField.website => TextInputType.url,
        CompanyInfoField.address => TextInputType.streetAddress,
      };

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final visible = CompanyInfoField.values
        .where((f) => modes[f] != CompanyInfoMode.off)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Company information', style: text.label),
        const SizedBox(height: 2),
        Text(
          'We verify these details against the official registry record.',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: MyazaSpacing.md),
        for (final field in visible) ...[
          BusinessFieldLabel(
            label: field.label,
            required: modes[field] == CompanyInfoMode.required,
          ),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaInput(
            controller: controllers[field],
            hint: field.placeholder,
            keyboardType: _keyboardFor(field),
            errorText: field == CompanyInfoField.email && !emailValid
                ? 'Enter a valid email address.'
                : null,
            onChanged: onChanged,
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],
      ],
    );
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
