import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/kyc_error_mapper.dart';

// Business (KYB) submissions fail with their own server error tokens. Before
// they were mapped, every one of them fell through to a bare `unknown` (or, for
// `pricing_not_configured`, read as a transient 5xx "try again in a moment"),
// so the user saw nothing actionable.

KYCError mapVerify(String error, {int statusCode = 422}) => mapToKycError(
      KYCApiException(statusCode: statusCode, error: error),
      context: ErrorContext.verify,
    );

void main() {
  group('KYB error mapping', () {
    test('workflow problems map to invalid_workflow', () {
      for (final token in [
        'workflow_not_found',
        'workflow_subject_mismatch',
        'country_mismatch',
        'product_unsupported',
      ]) {
        expect(mapVerify(token).code, 'invalid_workflow', reason: token);
        expect(mapVerify(token).message, isNotEmpty, reason: token);
      }
    });

    test('business_verifications_disabled maps to feature_disabled', () {
      final error = mapVerify('business_verifications_disabled', statusCode: 403);
      expect(error.code, 'feature_disabled');
      expect(error.message, contains('Business verification'));
    });

    test('input problems keep a friendly message under unknown', () {
      expect(
        mapVerify('registration_name_required').message,
        contains('registered business name'),
      );
      expect(
        mapVerify('only_test_ids_allowed').message,
        contains('test registration numbers'),
      );
    });

    test('pricing_not_configured beats the generic 5xx branch', () {
      // A 500 would otherwise read as "a server error occurred, try again in a
      // moment" — retrying never fixes unconfigured pricing.
      final error = mapVerify('pricing_not_configured', statusCode: 500);
      expect(error.code, 'unknown');
      expect(error.message, contains('pricing'));
      expect(error.message, isNot(contains('try again in a moment')));
    });

    test('incomplete application sections point back at the step', () {
      // These are recoverable — the SDK has screens for all three sections, so
      // the message must send the user back rather than declaring a dead end.
      for (final token in [
        'missing_documents',
        'missing_company_info',
        'key_people_required',
      ]) {
        final error = mapVerify(token);
        expect(error.code, 'unknown', reason: token);
        expect(error.message, contains('go back'), reason: token);
      }
    });
  });

  group('existing codes still map', () {
    test('402 insufficient credits carries its details', () {
      final error = mapToKycError(
        const KYCApiException(
          statusCode: 402,
          error: 'insufficient_credits',
          details: {'required': 100, 'balance': 10, 'currency': 'NGN'},
        ),
        context: ErrorContext.verify,
      );
      expect(error.code, 'insufficient_credits');
      expect(error.details?['required'], 100);
    });

    test('an unmapped 5xx is still a transient server error', () {
      final error = mapVerify('something_new', statusCode: 503);
      expect(error.code, 'network_error');
      expect(error.message, contains('try again in a moment'));
    });

    test('upload context falls back to upload_failed', () {
      final error = mapToKycError(
        const KYCApiException(statusCode: 400, error: 'bad_request'),
        context: ErrorContext.upload,
      );
      expect(error.code, 'upload_failed');
    });
  });
}
