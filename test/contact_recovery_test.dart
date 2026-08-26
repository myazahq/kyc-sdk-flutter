import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/contact_recovery.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

void main() {
  group('expiredContactChannels', () {
    test('reads the missing channels off a contact_verification_required 422', () {
      const err = KYCApiException(
        statusCode: 422,
        error: 'contact_verification_required',
        details: {
          'missing': ['email'],
        },
      );
      expect(expiredContactChannels(err), ['email']);
    });

    test('keeps both channels and drops anything unrecognised', () {
      const err = KYCApiException(
        statusCode: 422,
        error: 'contact_verification_required',
        details: {
          'missing': ['phone', 'email', 'fax'],
        },
      );
      expect(expiredContactChannels(err), ['phone', 'email']);
    });

    test('returns nothing for other errors or malformed bodies', () {
      expect(
        expiredContactChannels(
          const KYCApiException(statusCode: 422, error: 'questionnaire_invalid'),
        ),
        isEmpty,
      );
      expect(expiredContactChannels(Exception('network')), isEmpty);
      expect(
        expiredContactChannels(
          const KYCApiException(
            statusCode: 422,
            error: 'contact_verification_required',
          ),
        ),
        isEmpty,
      );
      expect(
        expiredContactChannels(
          const KYCApiException(
            statusCode: 422,
            error: 'contact_verification_required',
            details: {'missing': 'email'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('stepAfterContactVerified', () {
    test('defers to the ordinary forward walk outside recovery', () {
      expect(
        stepAfterContactVerified(recovery: false, expired: const [], channel: 'email'),
        isNull,
      );
    });

    test('returns straight to submitted in recovery', () {
      expect(
        stepAfterContactVerified(
            recovery: true, expired: const ['email'], channel: 'email'),
        KYCStep.submitted,
      );
    });

    test('visits the other still-refused channel before resubmitting', () {
      expect(
        stepAfterContactVerified(
            recovery: true, expired: const ['email', 'phone'], channel: 'email'),
        KYCStep.contactPhone,
      );
    });

    test('ignores its own channel still being flagged', () {
      expect(
        stepAfterContactVerified(
            recovery: true, expired: const ['phone'], channel: 'phone'),
        KYCStep.submitted,
      );
    });
  });

  group('KYCState contact recovery plumbing', () {
    test('clear flags null the tokens and copyWith carries the expired list', () {
      const state = KYCState(emailToken: 'tok_a', phoneToken: 'tok_b');
      final cleared = state.copyWith(
        clearEmailToken: true,
        expiredContact: ['email'],
      );
      expect(cleared.emailToken, isNull);
      expect(cleared.phoneToken, 'tok_b');
      expect(cleared.expiredContact, ['email']);
    });
  });
}
