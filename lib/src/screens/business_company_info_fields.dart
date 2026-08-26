import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/theme.dart';
import '../config/website.dart';
import '../widgets/myaza_input.dart';
import '../widgets/phone_number_input.dart';
import '../widgets/themed_sheet.dart';
import 'business_details_parts.dart';

// ─── The company profile a KYB workflow asks for ─────────────────────────────
//
// Each field's mode comes from the workflow and must match the server's
// resolution exactly — a field marked optional here but required there
// produces a 422 the user cannot act on. The last five are registry facts the
// applicant STATES: asked as their own answer rather than filled from the
// register, because where the two differ that is the finding. Field list,
// labels, placeholders and controls mirror the web SDK's
// BusinessCompanyInfoFields 1:1.

class BusinessCompanyInfoFields extends StatelessWidget {
  final Map<CompanyInfoField, CompanyInfoMode> modes;
  final Map<CompanyInfoField, TextEditingController> controllers;

  /// Seeds the phone dial code: the company's country of registration.
  final String country;

  /// The current E.164 business phone — the phone control keeps its own text,
  /// so the register's number reaches it through this rather than the
  /// controller map.
  final String phoneValue;
  final void Function(CompanyInfoField field, String value) onChanged;

  const BusinessCompanyInfoFields({
    super.key,
    required this.modes,
    required this.controllers,
    required this.country,
    required this.phoneValue,
    required this.onChanged,
  });

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
        for (final field in visible) ...[
          const SizedBox(height: MyazaSpacing.md),
          _field(context, field),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, CompanyInfoField field) {
    final required = modes[field] == CompanyInfoMode.required;
    final ctrl = controllers[field]!;
    final label = BusinessFieldLabel(label: field.label, required: required);

    switch (field) {
      case CompanyInfoField.phone:
        // The same control the phone-verification step uses: dial-code picker,
        // as-you-type national formatting, E.164 out. A business number is a
        // phone number, and a bare text box gets back a dozen different
        // shapes of the same digits. `value` carries the register's number
        // when the lookup returned one.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: MyazaSpacing.xs),
            PhoneNumberInput(
              defaultCountry: country,
              value: phoneValue,
              autofocus: false,
              onChanged: (e164, _) => onChanged(field, e164),
            ),
          ],
        );
      case CompanyInfoField.dateOfIncorporation:
        // A date gets the picker, not a text box — same control the
        // questionnaire uses; emits strict YYYY-MM-DD.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: MyazaSpacing.xs),
            _DateField(
              value: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
              placeholder: field.placeholder,
              onChanged: (iso) {
                ctrl.text = iso;
                onChanged(field, iso);
              },
            ),
          ],
        );
      default:
        final value = ctrl.text.trim();
        final error = switch (field) {
          CompanyInfoField.email
              when value.isNotEmpty && !isValidContactEmail(value) =>
            'Enter a valid email address.',
          CompanyInfoField.website
              when value.isNotEmpty && !isValidWebsite(value) =>
            'Enter a valid website, for example company.com',
          _ => null,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: MyazaSpacing.xs),
            MyazaInput(
              controller: ctrl,
              hint: field.placeholder,
              keyboardType: switch (field) {
                CompanyInfoField.email => TextInputType.emailAddress,
                CompanyInfoField.website => TextInputType.url,
                CompanyInfoField.address => TextInputType.streetAddress,
                _ => TextInputType.text,
              },
              // Names, IDs and URLs are proper nouns — autocorrect rewrites
              // them right before submission.
              autocorrect: field == CompanyInfoField.address ||
                  field == CompanyInfoField.natureOfBusiness,
              errorText: error,
              onChanged: (v) => onChanged(field, v),
            ),
          ],
        );
    }
  }
}

class _DateField extends StatelessWidget {
  final String? value;
  final String placeholder;
  final void Function(String iso) onChanged;

  const _DateField({
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
            Icon(Icons.calendar_today, size: 18, color: colors.textSecondary),
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
