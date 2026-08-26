import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business_application.dart';
import '../config/key_people_section_defs.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/myaza_button.dart';
import 'key_people_add_edit.dart';
import 'key_people_footer.dart';
import 'key_people_sections_list.dart';

// ─── Business key-people screen ───────────────────────────────────────────────
//
// "Directors & owners", in SECTIONS: beneficial owners, shareholders, directors
// & representatives. They are views over one shared list, not buckets, so a
// director who also holds 30% appears in both (key_people_sections.dart). The
// FORM lives in the add/edit sheet; the card's X takes a person out of the
// section they are shown in, which is not the same as deleting them.
//
// Mirrors the web SDK's BusinessKeyPeopleStep and the RN screen 1:1.

class BusinessKeyPeopleScreen extends ConsumerWidget {
  const BusinessKeyPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final rows = ref.watch(kYCNotifierProvider.select((s) => s.keyPeople));
    final business = ref.watch(kycConfigProvider).business;
    final minEntries = keyPeopleMinEntries(business);
    // Roles whose email is mandatory (the ones actually sent a verification
    // link) — threaded into every validity read so the card, the sheet and
    // the Continue gate agree on what "complete" means.
    final emailRequiredFor = keyPeopleRequireEmail(business);

    final validCount =
        rows.where((r) => r.isValidWith(emailRequiredFor)).length;
    final hasInvalid =
        rows.any((r) => !r.isBlank && !r.isValidWith(emailRequiredFor));
    final meetsMinimum = validCount >= minEntries;

    // Combined ownership above 100% is factually impossible — catch the typo
    // here rather than shipping it into the registry cross-check as a doomed
    // mismatch. Under 100% is fine (not every owner has to be listed).
    final totalPct = rows.fold<double>(0, (sum, r) => sum + keyPersonPct(r));
    final overAllocated = totalPct > 100;

    final threshold = keyPeopleThreshold(ref);

    void onContinue() {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      // Half-typed rows are dropped rather than submitted: an entry the user
      // abandoned is not a person they disclosed.
      notifier.setKeyPeople(rows
          .where((r) => r.isValidWith(emailRequiredFor))
          .toList(growable: false));
      notifier.nextStep();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No lead paragraph: the step HEADER carries "List the company's
        // directors and owners of 25% or more…" (myaza_kyc_widget.dart step
        // meta, matching the web SDK's StepHeader).
        if (rows.isEmpty && minEntries == 0)
          KeyPeopleHint(
            child: Text(
              "You can skip this if you're unsure. We'll identify directors "
              'and owners from the official registry. Adding them here speeds '
              'up the review.',
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          )
        else if (minEntries > 0 && validCount < minEntries)
          KeyPeopleHint(
            child: Text(
              'List at least $minEntries '
              '${minEntries == 1 ? 'person' : 'people'} to continue'
              '${validCount > 0 ? ' ($validCount of $minEntries added)' : ''}.',
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
            ),
          ),
        if (rows.isEmpty || (minEntries > 0 && validCount < minEntries))
          const SizedBox(height: MyazaSpacing.md),

        KeyPeopleSectionsList(
          sections: keyPeopleSectionList(business, threshold),
          rows: rows,
          threshold: threshold,
          emailRequiredFor: emailRequiredFor,
          uboUnidentifiable: ref.watch(
              kYCNotifierProvider.select((s) => s.uboUnidentifiable)),
          canAdd: rows.length < kMaxKeyPeopleRows,
          onRows: (next) =>
              ref.read(kYCNotifierProvider.notifier).setKeyPeople(next),
          onAdd: (section) => openKeyPersonEditor(context, ref, section: section),
          // The section comes WITH the tap: editing a card in Shareholders
          // must show the shareholder form, not the form for whichever hat
          // happens to be their strongest.
          onEdit: (section, index) =>
              openKeyPersonEditor(context, ref, index: index, section: section),
          onExemption: (v) =>
              ref.read(kYCNotifierProvider.notifier).setUboUnidentifiable(v),
        ),
        if (rows.length >= kMaxKeyPeopleRows) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(
            'You can list up to $kMaxKeyPeopleRows people here.',
            textAlign: TextAlign.center,
            style: text.bodyMedium.copyWith(color: colors.textMuted),
          ),
        ],
        const SizedBox(height: MyazaSpacing.md),

        KeyPeopleTotals(totalPct: totalPct),
        const SizedBox(height: MyazaSpacing.md),
        MyazaButton(
          label: 'Continue',
          onPressed: meetsMinimum && !hasInvalid && !overAllocated
              ? onContinue
              : null,
        ),
      ],
    );
  }
}
