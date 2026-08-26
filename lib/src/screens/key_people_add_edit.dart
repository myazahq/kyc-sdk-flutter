import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/key_people_section_defs.dart';
import '../config/key_people_sections.dart';
import '../providers/kyc_provider.dart';
import 'key_person_sheet.dart';

// Opening the add/edit sheet and folding its result back into the list. Split
// from business_key_people_screen (200-line rule): the screen renders, this
// mutates.

/// A row's declared stake, or zero. Shared so the sheet's "other owners total"
/// and the step's summary count the same thing.
double keyPersonPct(KeyPersonEntry row) => row.ownershipValue ?? 0;

/// The beneficial-ownership line in force: the workflow's own, else the
/// REGISTER's default (10 in Nigeria, 25 elsewhere). Never a literal 25, which
/// classified an NG flow at 25 on screen while the server read the submission
/// at 10, so the two disagreed about who was a beneficial owner.
double keyPeopleThreshold(WidgetRef ref) {
  final config = ref.read(kycConfigProvider);
  return config.business?.keyPeople?.ownershipThreshold ??
      defaultUboThreshold(
        ref.read(kYCNotifierProvider).businessCountry ??
            config.business?.country,
      );
}

Future<void> openKeyPersonEditor(
BuildContext context,
WidgetRef ref, {
  int? index,
  KeyPeopleSection? section,
}) async {
  final notifier = ref.read(kYCNotifierProvider.notifier);
  final state = ref.read(kYCNotifierProvider);
  final rows = state.keyPeople;
  // New people default to the business's registry country (picked on the
  // details step) — most directors are local, and a foreign one just
  // switches theirs.
  final defaultCountry = state.businessCountry ??
      ref.read(kycConfigProvider).business?.country ??
      '';
  final editing = index != null;
  // A person added FROM a section starts wearing that section's hat, so the
  // row lands in the list the applicant was looking at rather than wherever
  // the default role happens to put it.
  final seeded = section == null ? null : kSectionRole[section]!;
  final initial = editing
      ? rows[index]
      : KeyPersonEntry(
          country: defaultCountry,
          role: seeded ?? KeyPersonRole.director,
          roles: seeded == null ? const [] : [seeded],
        );
  final totalPct = rows.fold<double>(0, (sum, r) => sum + keyPersonPct(r));

  final result = await showKeyPersonSheet(
    context,
    editing: editing,
    // EDITING keeps the section the card was tapped in, so the form shows the
    // hat being edited rather than the person's strongest one.
    section: section ?? _sectionOf(rows[index!], keyPeopleThreshold(ref)),
    initial: initial,
    uboThreshold: keyPeopleThreshold(ref),
    corporateKyb: ref
            .read(kycConfigProvider)
            .business
            ?.keyPeople
            ?.corporateKyb ??
        false,
    otherPctTotal: editing ? totalPct - keyPersonPct(initial) : totalPct,
    emailRequiredFor:
        keyPeopleRequireEmail(ref.read(kycConfigProvider).business),
  );
  if (result == null) return;

  final current = ref.read(kYCNotifierProvider).keyPeople;
  switch (result) {
    case KeyPersonSaved(:final entry):
      notifier.setKeyPeople(editing
          ? [
              for (var i = 0; i < current.length; i++)
                i == index ? entry : current[i],
            ]
          : [...current, entry]);
    case KeyPersonRemoved():
      notifier.setKeyPeople([
        for (var i = 0; i < current.length; i++)
          if (i != index) current[i],
      ]);
  }
}

/// The section a card belongs to when the caller did not name one, which is
/// what happens on EDIT: the tap came from a section, and the form should show
/// the hat being edited. Falls back to the strongest section the entry meets.
KeyPeopleSection _sectionOf(KeyPersonEntry entry, double threshold) {
  final sections = sectionsFor(entry, threshold);
  for (final candidate in [
    KeyPeopleSection.ubos,
    KeyPeopleSection.representatives,
    KeyPeopleSection.shareholders,
  ]) {
    if (sections.contains(candidate)) return candidate;
  }
  return KeyPeopleSection.shareholders;
}
