import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

// Mirrors the web SDK's biometric-copy.test.ts and the RN biometricCopy test;
// the resolution rules are a contract the three keep.
const copy = BiometricCopy(
  waiting: BiometricCopyText(title: 'One moment, {firstName}', description: '  '),
  verified: BiometricCopyText(description: 'Welcome back, {firstName} {lastName}.'),
  declined: BiometricCopyText(title: '{firstName}, that did not match'),
);

void main() {
  test('fills the tokens and drops a field that empties out', () {
    final words = biometricCopyFor(
      scope: 'biometric-authentication',
      biometric: const BiometricFlowConfig(copy: copy),
      firstName: 'Ada',
      lastName: 'Okafor',
    );
    expect(words.waiting?.title, 'One moment, Ada');
    expect(words.waiting?.description, isNull);
    expect(words.verified?.title, isNull);
    expect(words.verified?.description, 'Welcome back, Ada Okafor.');
    expect(words.declined?.title, 'Ada, that did not match');
  });

  test('a title that is only a missing token falls back to the default, never a blank', () {
    final words = biometricCopyFor(
      scope: 'biometric-authentication',
      biometric: const BiometricFlowConfig(copy: BiometricCopy(waiting: BiometricCopyText(title: '{firstName}'))),
    );
    expect(words.waiting, isNull);
  });

  test('enrolment keeps the waiting words and ignores the verdict screens it never shows', () {
    final words = biometricCopyFor(
      scope: 'biometric-enrollment',
      biometric: const BiometricFlowConfig(copy: copy),
      firstName: 'Ada',
    );
    expect(words.waiting?.title, 'One moment, Ada');
    expect(words.verified, isNull);
    expect(words.declined, isNull);
  });

  test('is all-null off the biometric scopes and with no block', () {
    expect(biometricCopyFor(scope: 'address', biometric: const BiometricFlowConfig(copy: copy)).waiting, isNull);
    expect(biometricCopyFor(scope: 'biometric-authentication').waiting, isNull);
    expect(biometricCopyFor(biometric: const BiometricFlowConfig(copy: copy)).waiting, isNull);
  });

  test('fromJson trims blanks to absent, and the workflow merge keeps the copy per screen', () {
    final parsed = BiometricFlowConfig.fromJson({
      'copy': {
        'waiting': {'title': 'Hold on', 'description': '   '},
        'verified': {'description': 'Done.'},
      },
    });
    expect(parsed.copy?.waiting?.title, 'Hold on');
    expect(parsed.copy?.waiting?.description, isNull);
    final merged = const BiometricFlowConfig(
      copy: BiometricCopy(declined: BiometricCopyText(title: 'Not you')),
    ).merge(parsed);
    expect(merged.copy?.waiting?.title, 'Hold on');
    expect(merged.copy?.verified?.description, 'Done.');
    expect(merged.copy?.declined?.title, 'Not you');
  });

  test('the config extension reads the consumer userData', () {
    const config = MyazaKYCConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      scope: 'biometric-authentication',
      userData: UserData(firstName: 'Ada'),
      biometric: BiometricFlowConfig(copy: copy),
    );
    expect(config.biometricCopy.waiting?.title, 'One moment, Ada');
    expect(fillCopyTokens('Hi {firstName} {lastName}', firstName: 'Ada'), 'Hi Ada');
  });
}
