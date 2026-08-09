import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/theme.dart';
import '../widgets/country_field.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';

// ─── Key-person form fields ──────────────────────────────────────────────────
//
// Full name → role → ownership % → country → email, with the same live
// per-field validation the old inline row had. No card chrome, no header:
// this is the body of the add/edit sheet (key_person_sheet.dart), which owns
// the draft state, the controllers, and the save/remove actions.
//
// Mirrors the web SDK's KeyPersonForm and the RN SDK's KeyPersonForm 1:1.

/// "25" not "25.0" — the threshold is a whole number in practice.
String _fmtPct(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

class KeyPersonForm extends StatelessWidget {
  final KeyPersonEntry entry;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController pctCtrl;
  final ValueChanged<KeyPersonEntry> onChange;

  /// Ownership % at/above which the server treats a person as a beneficial
  /// owner (the workflow's `keyPeople.ownershipThreshold`, default 25).
  final double uboThreshold;

  /// Set when this draft's % would push the COMBINED ownership across all
  /// people past 100% — shown on the % field as a warning. It never blocks
  /// saving (the fix may live on a different person); the list's summary and
  /// the disabled Continue enforce the total.
  final String? combinedPctError;

  const KeyPersonForm({
    super.key,
    required this.entry,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.pctCtrl,
    required this.onChange,
    this.uboThreshold = 25,
    this.combinedPctError,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final name = entry.name.trim();
    final nameInvalid = entry.name.isNotEmpty && name.length < 2;
    final email = entry.email.trim();
    final emailInvalid = email.isNotEmpty && !isValidContactEmail(email);
    final pct = entry.ownershipPct.trim();
    final pctValue = double.tryParse(pct);
    final pctInvalid =
        pct.isNotEmpty && (pctValue == null || pctValue < 0 || pctValue > 100);
    // Surface the regulatory consequence as feedback: at/above the threshold
    // the server escalates this person to a beneficial owner regardless of the
    // role picked. Quiet when they already chose UBO — nothing new to say.
    final uboHint = !pctInvalid &&
        pctValue != null &&
        pctValue >= uboThreshold &&
        entry.role != KeyPersonRole.beneficialOwner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Full name', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: nameCtrl,
          hint: 'e.g. Bola Owner',
          // It's a person's name — start every word capitalized.
          textCapitalization: TextCapitalization.words,
          errorText: nameInvalid ? "Enter the person's full name." : null,
          onChanged: (v) => onChange(entry.copyWith(name: v)),
        ),
        const SizedBox(height: MyazaSpacing.md),

        Text('Role', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaSelect<KeyPersonRole>(
          value: entry.role,
          sheetTitle: 'Role',
          options: [
            for (final role in KeyPersonRole.values)
              MyazaSelectOption(value: role, label: role.label),
          ],
          onChanged: (v) => onChange(entry.copyWith(role: v)),
        ),
        const SizedBox(height: MyazaSpacing.md),

        Text.rich(TextSpan(children: [
          TextSpan(text: 'Ownership %', style: text.label),
          TextSpan(
            text: ' (optional)',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ])),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: pctCtrl,
          hint: entry.role.isOwnerRole ? 'e.g. 60' : '—',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          suffix: Text(
            '%',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
          errorText:
              pctInvalid ? 'Enter a value between 0 and 100.' : combinedPctError,
          helperText: uboHint
              ? 'At ${_fmtPct(uboThreshold)}% or more, this person counts as a beneficial owner.'
              : null,
          onChanged: (v) => onChange(entry.copyWith(ownershipPct: v)),
        ),
        const SizedBox(height: MyazaSpacing.md),

        Text.rich(TextSpan(children: [
          TextSpan(text: 'Country', style: text.label),
          TextSpan(
            text: ' (where their ID was issued)',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ])),
        const SizedBox(height: MyazaSpacing.xs),
        // The SAME sheet as the phone field's dial-code picker
        // (keyboard-aware, autofocused search, results pinned above the
        // keys) — minus the dial codes. Two country pickers that feel
        // different would read as a bug.
        CountryField(
          country: entry.country,
          onChanged: (v) => onChange(entry.copyWith(country: v)),
        ),
        const SizedBox(height: MyazaSpacing.md),

        Text.rich(TextSpan(children: [
          TextSpan(text: 'Email', style: text.label),
          TextSpan(
            text: ' (optional — used to send their verification link)',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ])),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: emailCtrl,
          hint: 'name@company.com',
          keyboardType: TextInputType.emailAddress,
          errorText: emailInvalid ? 'Enter a valid email address.' : null,
          onChanged: (v) => onChange(entry.copyWith(email: v)),
        ),
      ],
    );
  }
}
