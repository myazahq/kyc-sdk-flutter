import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_business.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business_application.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/key_people_prefill.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

void main() {
  const flitstack = [
    RegistryOfficer(name: 'MBOTO IBI', designation: 'PRESENTER'),
    RegistryOfficer(name: 'Atambi Tony Joseph', designation: 'WITNESS'),
    RegistryOfficer(name: 'Archibong Bassey Charles', designation: 'DIRECTOR'),
    RegistryOfficer(name: 'Archibong Bassey Charles', designation: 'SHAREHOLDER'),
    RegistryOfficer(name: 'Ingwe Unimke Richard', designation: 'DIRECTOR'),
    RegistryOfficer(
        name: 'Ingwe Unimke Richard',
        designation: 'PERSONS WITH SIGNIFICANT CONTROL'),
  ];

  group('prefillKeyPeople', () {
    test('offers one row per person and drops the filing agent and witness', () {
      final rows = prefillKeyPeople(flitstack, 'NG');
      expect(rows.map((r) => r.name).toList(),
          ['Archibong Bassey Charles', 'Ingwe Unimke Richard']);
    });

    test('keeps the classification that asks the most of them', () {
      final rows = prefillKeyPeople(flitstack, 'NG');
      expect(rows[1].role, KeyPersonRole.beneficialOwner);
    });

    test('never merges siblings who share a double-barrelled surname', () {
      final rows = prefillKeyPeople(const [
        RegistryOfficer(name: 'Amara Sandbox-Parent', designation: 'SHAREHOLDER'),
        RegistryOfficer(name: 'Femi Sandbox-Parent', designation: 'DIRECTOR'),
      ], 'NG');
      expect(rows, hasLength(2));
    });

    test('marks a corporate shareholder as a company', () {
      final rows = prefillKeyPeople(const [
        RegistryOfficer(name: 'Acme Holdings Ltd', designation: 'SHAREHOLDER'),
      ], 'NG');
      expect(rows.single.isCorporate, isTrue);
    });
  });

  group('shouldPrefill', () {
    test('only ever fills an empty list', () {
      expect(shouldPrefill(const []), isTrue);
      expect(shouldPrefill(const [KeyPersonEntry()]), isTrue);
      expect(shouldPrefill(const [KeyPersonEntry(name: 'Someone Typed')]), isFalse);
    });
  });

  group('what the register already answered', () {
    // Dropping the register's own answers is not neutral: the applicant
    // retypes a split it computed, and an email it holds goes missing until
    // the step refuses to continue without one.
    test('carries the email and the split it gave', () {
      final rows = prefillKeyPeople(const [
        RegistryOfficer(
          name: 'Bola Owner',
          designation: 'Person with significant control',
          ownershipPct: 45,
          email: 'bola@example.com',
        ),
      ], 'NG');
      expect(rows.single.email, 'bola@example.com');
      // 45, not "45.0": it lands in a box the applicant may edit.
      expect(rows.single.ownershipPct, '45');
    });

    test('invents nothing it did not give', () {
      final rows = prefillKeyPeople(
          const [RegistryOfficer(name: 'Jane Doe', designation: 'Director')],
          'NG');
      expect(rows.single.email, '');
      expect(rows.single.ownershipPct, '');
    });

    test('a merged person keeps what only one of their filings carried', () {
      // One designation per entry, so the email can sit on the director row
      // and the stake on the shareholder row.
      final rows = prefillKeyPeople(const [
        RegistryOfficer(
            name: 'Chidi Pep', designation: 'Director', email: 'c@example.com'),
        RegistryOfficer(
            name: 'Chidi Pep',
            designation: 'Person with significant control',
            ownershipPct: 30),
      ], 'NG');
      expect(rows, hasLength(1));
      expect(rows.single.email, 'c@example.com');
      expect(rows.single.ownershipPct, '30');
    });

    test("its own word on corporate beats the name heuristic", () {
      // Null is SILENCE, not a denial, so the heuristic answers only then.
      final said = prefillKeyPeople(const [
        RegistryOfficer(
            name: 'Ada Trust', designation: 'Shareholder', isCorporate: true),
      ], 'NG');
      expect(said.single.isCorporate, isTrue);
    });
  });
}
