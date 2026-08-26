import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_progress.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_restore.dart';

// A resumed session's stored progress hydrates the state — the Flutter mirror
// of web's RESTORE_PROGRESS. Round-trips through progressFromState so the
// writer and the reader can never drift.

void main() {
  _resumeGuards();

  test('restores step, captures and typed data', () {
    final s = restoredState(const KYCState(), {
      'step': 'id-input',
      'mediaIds': {'documentFront': 'med_1', 'selfie': 'med_2'},
      'data': {
        'selectedCountry': 'NG',
        'selectedIdType': 'bvn',
        'idNumber': '12345678901',
        'questionnaireAnswers': {'source_of_funds': 'salary'},
      },
    });
    expect(s.currentStep, KYCStep.idInput);
    expect(s.mediaIds.documentFront, 'med_1');
    expect(s.mediaIds.selfie, 'med_2');
    expect(s.selectedCountry, 'NG');
    expect(s.selectedIdType?.key, 'bvn');
    expect(s.idNumber, '12345678901');
    expect(s.questionnaireAnswers['source_of_funds'], 'salary');
  });

  test('restores a KYB application including key people', () {
    final s = restoredState(const KYCState(), {
      'step': 'business-key-people',
      'data': {
        'business': {
          'country': 'NG',
          'registrationNumber': 'RC123456',
          'registrationName': 'Acme Ltd',
        },
        'businessApplication': {
          'keyPeople': [
            {
              'name': 'Bola Owner',
              'role': 'beneficial_owner',
              'ownershipPct': 60,
              'isCorporate': false,
            },
            {
              'name': 'Sandbox Holdings Ltd',
              'role': 'shareholder',
              'isCorporate': true,
              'registrationNumber': 'RC0000900',
            },
          ],
          'applicantRole': 'director',
          'applicantName': 'Jane',
        },
      },
    });
    expect(s.currentStep, KYCStep.businessKeyPeople);
    expect(s.businessCountry, 'NG');
    expect(s.registrationNumber, 'RC123456');
    expect(s.keyPeople, hasLength(2));
    expect(s.keyPeople.first.role, KeyPersonRole.beneficialOwner);
    expect(s.keyPeople.first.ownershipPct, '60');
    expect(s.keyPeople.last.isCorporate, isTrue);
    expect(s.applicantRole, ApplicantRole.director);
    expect(s.applicantName, 'Jane');
  });

  test('round-trips its own snapshot', () {
    final original = restoredState(const KYCState(), {
      'step': 'liveness',
      'mediaIds': {'documentFront': 'med_1'},
      'data': {'selectedCountry': 'NG', 'selectedIdType': 'passport'},
    });
    final snapshot = progressFromState(original);
    final replayed = restoredState(const KYCState(), snapshot);
    expect(replayed.currentStep, original.currentStep);
    expect(replayed.selectedCountry, original.selectedCountry);
    expect(replayed.selectedIdType?.key, original.selectedIdType?.key);
    expect(replayed.mediaIds.documentFront, 'med_1');
  });

  test('an empty snapshot leaves the state untouched', () {
    const before = KYCState();
    final after = restoredState(before, const {});
    expect(after.currentStep, before.currentStep);
    expect(after.selectedCountry, isNull);
    expect(after.keyPeople, isEmpty);
  });
}

// ─── Resuming must never land somewhere the applicant cannot act ─────────────
//
// This SDK keeps the ID type as a RESOLVED definition, not a key, so rebuilding
// it needs a country. A real session stored `selectedIdType: nin` and no
// `selectedCountry` — the applicant never picked one, because the flow took it
// from the config — so the ID type could not be rebuilt while the STEP was
// restored regardless. The app opened on "Enter your ID number" with no ID
// type: nothing to validate the number against, Continue permanently disabled,
// and no explanation on screen.
void _resumeGuards() {
  test('rebuilds the ID type from the flow country when none was stored', () {
    final s = restoredState(
      const KYCState(),
      {
        'step': 'id-input',
        'data': {'selectedIdType': 'nin'},
      },
      fallbackCountry: 'NG',
    );

    expect(s.selectedIdType?.key, 'nin');
    expect(s.selectedCountry, 'NG');
    expect(s.currentStep, KYCStep.idInput, reason: 'the step is walkable now');
  });

  test('falls back to the ID picker when the ID type cannot be rebuilt', () {
    // No stored country and no fallback: the ID type is unknowable, so the ID
    // screen is a dead end. Somewhere they can act beats somewhere they can sit.
    final s = restoredState(const KYCState(), {
      'step': 'id-input',
      'data': {'selectedIdType': 'nin'},
    });

    expect(s.selectedIdType, isNull);
    expect(s.currentStep, KYCStep.idType);
  });

  test('guards every step that needs an ID type, not just the number screen', () {
    for (final step in ['document-capture', 'nfc']) {
      final s = restoredState(const KYCState(), {
        'step': step,
        'data': {'selectedIdType': 'nin'},
      });
      expect(s.currentStep, KYCStep.idType, reason: '$step needs an ID type');
    }
  });

  test('leaves steps that do not need an ID type alone', () {
    final s = restoredState(const KYCState(), {'step': 'consent', 'data': {}});
    expect(s.currentStep, KYCStep.consent);
  });

  test('an explicit pick still wins over the flow country', () {
    final s = restoredState(
      const KYCState(),
      {
        'step': 'id-input',
        'data': {'selectedCountry': 'GH', 'selectedIdType': 'ghana-card'},
      },
      fallbackCountry: 'NG',
    );
    expect(s.selectedCountry, 'GH');
  });

  test('the writer stores the flow country so the snapshot describes itself', () {
    // Without this the reader has to guess, and a reader that guesses wrong
    // rebuilds the wrong ID type.
    final payload = progressFromState(
      const KYCState(currentStep: KYCStep.idInput),
      effectiveCountryValue: 'NG',
    );
    expect((payload['data'] as Map)['selectedCountry'], 'NG');
  });

  test('a failed submission is not a position to resume onto', () {
    // The trap: a 422 still writes `submitted` as the last step reached, so
    // reopening resumed there, submitted again, failed the same way and wrote
    // it again. Closing and reopening landed straight back on the error.
    final restored = restoredState(
      const KYCState(currentStep: KYCStep.consent),
      {
        'step': 'submitted',
        'data': {'businessCountry': 'NG'},
      },
      fallbackCountry: 'NG',
    );
    expect(restored.currentStep, isNot(KYCStep.submitted));
  });
}
