import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business_application.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/key_people_section_defs.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/key_people_sections.dart';

// Sections are VIEWS over one list, and the classification has to match what
// the SERVER will make of the same submission. Where it does not, the screen
// files somebody as a shareholder and the server files them as a beneficial
// owner, and nobody finds out until a reviewer asks why a UBO was never
// verified.

KeyPersonEntry person({
  String name = 'A Person',
  KeyPersonRole role = KeyPersonRole.director,
  List<KeyPersonRole> roles = const [],
  String pct = '',
  bool corporate = false,
}) =>
    KeyPersonEntry(
      name: name,
      role: role,
      roles: roles,
      ownershipPct: pct,
      isCorporate: corporate,
    );

void main() {
  group('who belongs where', () {
    test('a director holding 30% is in BOTH sections, not one', () {
      // The whole reason a section is not a bucket. The register files them
      // twice and so must the screen.
      final sections = sectionsFor(
          person(role: KeyPersonRole.director, pct: '30'), 25);
      expect(sections, contains(KeyPeopleSection.representatives));
      expect(sections, contains(KeyPeopleSection.ubos));
    });

    test('a stake at the line escalates, exactly as the server escalates it',
        () {
      expect(sectionsFor(person(role: KeyPersonRole.shareholder, pct: '25'), 25),
          contains(KeyPeopleSection.ubos));
      expect(
          sectionsFor(person(role: KeyPersonRole.shareholder, pct: '24'), 25),
          isNot(contains(KeyPeopleSection.ubos)));
    });

    test('a company is never a beneficial owner, whatever it holds', () {
      // A beneficial owner is a natural person in every regime that defines
      // one, so a 90% corporate holder stays a shareholder.
      final sections = sectionsFor(person(corporate: true, pct: '90'), 25);
      expect(sections, isNot(contains(KeyPeopleSection.ubos)));
      expect(sections, contains(KeyPeopleSection.shareholders));
    });

    test('a person the UBO section claimed is not also a plain shareholder',
        () {
      // Same stake, one classification.
      final sections =
          sectionsFor(person(role: KeyPersonRole.shareholder, pct: '60'), 25);
      expect(sections, contains(KeyPeopleSection.ubos));
      expect(sections, isNot(contains(KeyPeopleSection.shareholders)));
    });
  });

  group('granting and removing a hat', () {
    test('quick-add adds a role and re-reads the headline by precedence', () {
      final granted =
          grantRole(person(role: KeyPersonRole.signatory), KeyPeopleSection.ubos);
      expect(granted.roles, contains(KeyPersonRole.beneficialOwner));
      expect(granted.roles, contains(KeyPersonRole.signatory));
      // Beneficial owner outranks signatory.
      expect(granted.role, KeyPersonRole.beneficialOwner);
    });

    test('a company is never offered as a quick-add UBO', () {
      // A shareholder, its natural role: already a member THERE, so the only
      // question left is whether the other two sections offer it.
      final rows = [
        person(
            name: 'Holdings Ltd',
            corporate: true,
            role: KeyPersonRole.shareholder),
      ];
      expect(quickAddCandidates(rows, KeyPeopleSection.ubos, 25), isEmpty);
      expect(quickAddCandidates(rows, KeyPeopleSection.representatives, 25),
          [0]);
    });

    test('removing the last hat means removing the person', () {
      expect(
          withoutSection(person(role: KeyPersonRole.director),
              KeyPeopleSection.representatives, 25),
          isNull);
    });

    test('removing one hat keeps a person who wears another', () {
      final next = withoutSection(
        person(roles: const [
          KeyPersonRole.director,
          KeyPersonRole.beneficialOwner,
        ]),
        KeyPeopleSection.ubos,
        25,
      );
      expect(next, isNotNull);
      expect(next!.roles, [KeyPersonRole.director]);
    });

    test('"remove from UBOs" on someone held there by a STAKE removes them',
        () {
      // Dropping the role would not take them out of the section, so the tap
      // has to mean more than that or it would silently do nothing.
      expect(
        withoutSection(person(role: KeyPersonRole.shareholder, pct: '60'),
            KeyPeopleSection.ubos, 25),
        isNull,
      );
    });
  });

  group('the printed threshold is the one in force', () {
    test('Nigeria files significant control from a lower bar', () {
      // The server's uboThresholdFor. Printing 25 to an NG applicant while the
      // submission is read at 10 is a band they would plan around.
      expect(defaultUboThreshold('NG'), 10);
      expect(defaultUboThreshold('ng'), 10);
      expect(defaultUboThreshold('GH'), 25);
      expect(defaultUboThreshold(null), 25);
    });

    test('the definition prints the real number, not a rounded double', () {
      final sections = keyPeopleSectionList(null, 10);
      final ubos =
          sections.firstWhere((s) => s.key == KeyPeopleSection.ubos);
      expect(ubos.description, contains('10%'));
      expect(ubos.description, isNot(contains('10.0')));
    });
  });

  group('a chip is only offered when tapping it would do something', () {
    test('a beneficial owner is NOT offered under shareholders', () {
      // Membership is DERIVED, so granting the role does not always produce
      // it: same stake, one classification. The chip was offered anyway and
      // tapping it moved nobody, which reads as a broken app.
      final rows = [person(role: KeyPersonRole.beneficialOwner, pct: '60')];
      expect(quickAddCandidates(rows, KeyPeopleSection.shareholders, 25),
          isEmpty);
    });

    test('but they ARE offered under representatives, where it works', () {
      final rows = [person(role: KeyPersonRole.beneficialOwner, pct: '60')];
      expect(quickAddCandidates(rows, KeyPeopleSection.representatives, 25),
          [0]);
    });
  });
}
