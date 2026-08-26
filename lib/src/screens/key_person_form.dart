import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/key_people_sections.dart';
import '../config/theme.dart';
import '../widgets/country_field.dart';
import '../widgets/myaza_input.dart';
import 'key_person_kind_toggle.dart';
import 'key_person_role_chips.dart';
import 'ownership_slider.dart';
import 'key_person_owners.dart';

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
  final TextEditingController titleCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController pctCtrl;
  final TextEditingController registrationCtrl;
  final ValueChanged<KeyPersonEntry> onChange;

  /// Ownership % at/above which the server treats a person as a beneficial
  /// owner (the workflow's `keyPeople.ownershipThreshold`, default 25).
  final double uboThreshold;

  /// Nested KYB is on: a company listed here receives its own business
  /// application rather than only being screened. It changes what we tell the
  /// applicant, which is the whole reason the flag reaches this form.
  final bool corporateKyb;

  /// Set when this draft's % would push the COMBINED ownership across all
  /// people past 100% — shown on the % field as a warning. It never blocks
  /// saving (the fix may live on a different person); the list's summary and
  /// the disabled Continue enforce the total.
  final String? combinedPctError;

  /// Roles whose email is mandatory (they are sent a verification link).
  final Set<KeyPersonRole> emailRequiredFor;

  /// The section whose add tile or card opened the sheet. It already said what
  /// this person IS, which is why there is no coarse role dropdown: the UBO
  /// form asks name/stake/country/email, the shareholder form adds the
  /// person-or-company toggle, and the representative form picks between the
  /// real classifications as chips.
  final KeyPeopleSection section;

  const KeyPersonForm({
    super.key,
    required this.entry,
    required this.nameCtrl,
    required this.titleCtrl,
    required this.section,
    required this.emailCtrl,
    required this.pctCtrl,
    required this.registrationCtrl,
    required this.onChange,
    this.uboThreshold = 25,
    this.corporateKyb = false,
    this.combinedPctError,
    this.emailRequiredFor = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final name = entry.name.trim();
    final nameInvalid = entry.name.isNotEmpty && name.length < 2;
    final email = entry.email.trim();
    final emailInvalid = email.isNotEmpty && !isValidContactEmail(email);
    final needsEmail = rowNeedsEmail(entry, emailRequiredFor);
    final pct = entry.ownershipPct.trim();
    final pctValue = double.tryParse(pct);
    final pctInvalid =
        pct.isNotEmpty && (pctValue == null || pctValue < 0 || pctValue > 100);
    // Surface the regulatory consequence as feedback: at/above the threshold
    // the server escalates this person to a beneficial owner regardless of the
    // role picked. Quiet when they already chose UBO — nothing new to say.
    final corp = entry.isCorporate;
    final uboHint = !corp &&
        !pctInvalid &&
        pctValue != null &&
        pctValue >= uboThreshold &&
        entry.role != KeyPersonRole.beneficialOwner;

    final roleSet = rolesOf(entry);
    void setRoles(List<KeyPersonRole> next) => onChange(
        entry.copyWith(roles: next, role: primaryRole(next)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A beneficial owner is a natural person in every regime that defines
        // one, and a representative form is about the people who act, so only
        // the shareholder form offers the company option.
        if (section == KeyPeopleSection.shareholders)
          KeyPersonKindToggle(
          isCorporate: corp,
          // Beneficial ownership is a claim about a person, so switching to a
          // company reads the role down rather than leaving an impossible one.
          onChanged: (v) => onChange(entry.copyWith(
            isCorporate: v,
            role: v && entry.role == KeyPersonRole.beneficialOwner
                ? KeyPersonRole.shareholder
                : entry.role,
            registrationNumber: v ? entry.registrationNumber : '',
            owners: v ? entry.owners : const [],
          )),
        ),
        if (section == KeyPeopleSection.shareholders)
          const SizedBox(height: MyazaSpacing.md),

        Text(corp ? 'Company name' : 'Full name', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: nameCtrl,
          hint: corp ? 'e.g. Acme Holdings Ltd' : 'e.g. Bola Owner',
          // It's a name — start every word capitalized.
          textCapitalization: TextCapitalization.words,
          errorText: nameInvalid
              ? 'Enter the ${corp ? 'registered company name' : "person's full name"}.'
              : null,
          onChanged: (v) => onChange(entry.copyWith(name: v)),
        ),
        const SizedBox(height: MyazaSpacing.md),

        if (section == KeyPeopleSection.representatives) ...[
          KeyPersonRoleChips(roles: roleSet, onRoles: setRoles),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // The human nuance the closed role vocabulary cannot carry. A company
        // has no job title.
        if (!corp) ...[
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Position or title', style: text.label),
            TextSpan(
              text: ' (optional)',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ])),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaInput(
            controller: titleCtrl,
            hint: 'e.g. CFO, Board Member',
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => onChange(entry.copyWith(title: v)),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

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
              : corp && !pctInvalid && pct.isNotEmpty
                  ? (corporateKyb
                      ? 'A company is never a beneficial owner. This one will '
                          'need its own KYB verification: it receives a link to '
                          'a business application of its own, where the people '
                          'who own it are identified.'
                      : 'A company is never a beneficial owner. We check it '
                          'against sanctions lists, and the people who own it '
                          'are reviewed separately.')
                  : null,
          onChanged: (v) => onChange(entry.copyWith(ownershipPct: v)),
        ),
        // The fast coarse gesture beside the exact box. It rests at 0 for an
        // undeclared stake, so an untouched slider still submits "not
        // declared" rather than a confident zero.
        OwnershipSlider(
          value: pctValue ?? 0,
          onChanged: (next) {
            final text = next.round().toString();
            pctCtrl.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
            onChange(entry.copyWith(ownershipPct: text));
          },
        ),
        const SizedBox(height: MyazaSpacing.md),

        if (corp) ...[
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Registration number', style: text.label),
            TextSpan(
              text: ' (optional)',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ])),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaInput(
            controller: registrationCtrl,
            hint: 'e.g. RC123456',
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => onChange(entry.copyWith(registrationNumber: v)),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        Text.rich(TextSpan(children: [
          TextSpan(text: 'Country', style: text.label),
          TextSpan(
            text: corp ? ' (where it is registered)' : ' (where their ID was issued)',
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

        if (corp) ...[
          KeyPersonOwners(
            owners: entry.owners,
            companyName: entry.name,
            onChanged: (owners) => onChange(entry.copyWith(owners: owners)),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        Text.rich(TextSpan(children: [
          TextSpan(text: 'Email', style: text.label),
          if (needsEmail)
            TextSpan(
              text: ' *',
              style: text.label.copyWith(color: MyazaColors.error),
            )
          else
            TextSpan(
              text: corp
                  ? ' (optional)'
                  : ' (optional, used to send their verification link)',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
        ])),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: emailCtrl,
          hint: 'name@company.com',
          keyboardType: TextInputType.emailAddress,
          errorText: emailInvalid ? 'Enter a valid email address.' : null,
          helperText: needsEmail && email.isEmpty
              ? 'Required: this is how they receive their own verification link.'
              : null,
          onChanged: (v) => onChange(entry.copyWith(email: v)),
        ),
      ],
    );
  }
}
