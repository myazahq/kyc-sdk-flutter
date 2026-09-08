import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/biometric_auth.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// Face re-auth mirrors the web and RN SDKs: the error vocabulary an
// integrator branches on, and the one structural rule — the flow hosts the
// real liveness screen and never the submitted one, so a re-auth can never
// turn into a /verify.

void main() {
  group('mapBiometricAuthError', () {
    KYCApiException api(int status, [String error = 'x']) =>
        KYCApiException(statusCode: status, error: error);

    test('names not-enrolled, credits and key problems; else network', () {
      expect(mapBiometricAuthError(api(404, 'not_enrolled')).code, 'unknown');
      expect(mapBiometricAuthError(api(402)).code, 'insufficient_credits');
      expect(mapBiometricAuthError(api(401)).code, 'invalid_api_key');
      expect(mapBiometricAuthError(api(403)).code, 'invalid_api_key');
      expect(mapBiometricAuthError(api(500)).code, 'network_error');
      expect(mapBiometricAuthError(StateError('boom')).code, 'network_error');
    });
  });

  test('the response parses the verdict, not the status string', () {
    final r = BiometricAuthResponse.fromJson({
      'authenticated': false,
      'status': 'no_match',
      'confidence': 40,
      'live': true,
      'attemptId': 'ba_1',
    });
    expect(r.authenticated, isFalse);
    expect(r.confidence, 40.0);
    expect(r.token, isNull);
  });

  test("labels the trigger with the org's name when it has one", () {
    expect(defaultReauthLabel('Acme'), "Verify it's you with Acme");
    expect(defaultReauthLabel(null), "Verify it's you");
  });

  test('the flow hosts the real liveness screen and never the submitted one',
      () {
    final src =
        File('lib/src/widgets/myaza_biometric_auth.dart').readAsStringSync();
    expect(src, contains('LivenessScreen(onError:'));
    expect(src, isNot(contains('SubmittedScreen')));
    expect(src, isNot(contains('.verify(')));
  });
}
