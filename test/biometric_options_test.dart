import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

// Mirrors the server's biometric-options.test.ts and the web/RN SDKs' tests;
// the defaults are a contract the four keep together.
void main() {
  test('re-authentication hides the review, waits for the verdict and shows Done by default', () {
    final o = biometricFlowOptions(scope: 'biometric-authentication')!;
    expect(o.selfieReview, isFalse);
    expect(o.resultDelivery, 'both');
    expect(o.doneButton, isTrue);
    expect(showsSelfieReview(scope: 'biometric-authentication'), isFalse);
    expect(waitsForResult(scope: 'biometric-authentication'), isTrue);
    expect(showsDoneButton(scope: 'biometric-authentication'), isTrue);
  });

  test('honours an explicit review, a webhook delivery and a hidden Done button', () {
    const block = BiometricFlowConfig(selfieReview: true, resultDelivery: 'webhook', doneButton: false);
    final o = biometricFlowOptions(scope: 'biometric-authentication', biometric: block)!;
    expect(o.selfieReview, isTrue);
    expect(o.resultDelivery, 'webhook');
    expect(o.doneButton, isFalse);
    expect(showsSelfieReview(scope: 'biometric-authentication', biometric: block), isTrue);
    expect(waitsForResult(scope: 'biometric-authentication', biometric: block), isFalse);
    expect(showsDoneButton(scope: 'biometric-authentication', biometric: block), isFalse);
  });

  test("an app-only delivery waits exactly as the default does; the difference is the server's webhook", () {
    expect(waitsForResult(scope: 'biometric-authentication', biometric: const BiometricFlowConfig(resultDelivery: 'app')), isTrue);
    expect(waitsForResult(scope: 'biometric-authentication', biometric: const BiometricFlowConfig(resultDelivery: 'both')), isTrue);
  });

  test('enrolment hides the review too, never waits, and can hide Done', () {
    final o = biometricFlowOptions(scope: 'biometric-enrollment')!;
    expect(o.selfieReview, isFalse);
    expect(o.resultDelivery, isNull);
    expect(o.doneButton, isTrue);
    expect(waitsForResult(scope: 'biometric-enrollment', biometric: const BiometricFlowConfig(resultDelivery: 'app')), isFalse);
    expect(showsDoneButton(scope: 'biometric-enrollment', biometric: const BiometricFlowConfig(doneButton: false)), isFalse);
  });

  test('a full verification always reviews, never waits and always shows Done, whatever the block says', () {
    expect(biometricFlowOptions(), isNull);
    expect(showsSelfieReview(biometric: const BiometricFlowConfig(selfieReview: false)), isTrue);
    expect(waitsForResult(scope: 'address', biometric: const BiometricFlowConfig(resultDelivery: 'both')), isFalse);
    expect(showsDoneButton(scope: 'contact', biometric: const BiometricFlowConfig(doneButton: false)), isTrue);
  });

  test('fromJson keeps only the three known deliveries; merge is per field', () {
    expect(BiometricFlowConfig.fromJson({'resultDelivery': 'later'}).resultDelivery, isNull);
    expect(BiometricFlowConfig.fromJson({'resultDelivery': 'app'}).resultDelivery, 'app');
    final merged = const BiometricFlowConfig(doneButton: false).merge(const BiometricFlowConfig(selfieReview: true));
    expect(merged.selfieReview, isTrue);
    expect(merged.doneButton, isFalse);
  });

  test('the config extension asks the same three questions', () {
    const config = MyazaKYCConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      scope: 'biometric-authentication',
      biometric: BiometricFlowConfig(doneButton: false),
    );
    expect(config.showsSelfieReviewOption, isFalse);
    expect(config.waitsForResultOption, isTrue);
    expect(config.showsDoneButtonOption, isFalse);
  });
}
