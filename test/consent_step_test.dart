import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_progress.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── The consent screen switched off (`consentStep: false`) ──────────────────
//
// The host app has already asked, so the flow opens on its first real step.
// Every branch of the step order builds its head from the flag; the provider
// opens and resets on `openingStep`, the progress saver judges "untouched"
// against it and the widget hides Back on it. Mirrors the web and RN tests.

MyazaKYCConfig _config({
  bool consentStep = false,
  String? scope,
  String subjectType = 'individual',
  List<WorkflowCountryOption>? countries,
  EmailVerificationConfig? email,
}) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      consentStep: consentStep,
      scope: scope,
      subjectType: subjectType,
      countries: countries,
      emailVerification: email,
      addressCollection: scope == 'address'
          ? const AddressCollectionConfig(enabled: true)
          : null,
    );

void main() {
  test('is on by default and is what the classic flow opens on', () {
    expect(const MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG').consentStep, isTrue);
    expect(openingStep(_config(consentStep: true)), KYCStep.consent);
  });

  test('opens the individual flow on the ID list, the country picker, or the contact codes', () {
    expect(openingStep(_config()), KYCStep.idType);
    expect(
      openingStep(_config(countries: const [
        WorkflowCountryOption(country: 'NG'),
        WorkflowCountryOption(country: 'GH'),
      ])),
      KYCStep.countrySelect,
    );
    expect(
      openingStep(_config(email: const EmailVerificationConfig(enabled: true))),
      KYCStep.contactEmail,
    );
    expect(buildStepOrder(_config(), const KYCState()), isNot(contains(KYCStep.consent)));
  });

  test('opens a KYB flow on the business form and a scoped flow on its own check', () {
    expect(openingStep(_config(subjectType: 'business')), KYCStep.businessDetails);
    expect(openingStep(_config(scope: 'biometric-authentication')), KYCStep.liveness);
    expect(openingStep(_config(scope: 'address')), KYCStep.addressCollection);
  });

  test('rides a resolved workflow like every other template key', () {
    final flow = WorkflowResolution.fromJson({
      'flow': {'id': 'wf_x', 'name': 'Face', 'version': 1},
      'config': {'country': 'NG', 'consentStep': false},
      'environment': 'SANDBOX',
      'idTypes': <dynamic>[],
    });
    final merged = mergeWorkflowIntoConfig(
      const MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG'),
      flow.config,
    );
    expect(merged.consentStep, isFalse);
    // A flow that says nothing leaves the consumer's own setting alone.
    final silent = WorkflowResolution.fromJson({
      'flow': {'id': 'wf_y', 'name': 'Silent', 'version': 1},
      'config': {'country': 'NG'},
      'environment': 'SANDBOX',
      'idTypes': <dynamic>[],
    });
    expect(
      mergeWorkflowIntoConfig(const MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG'), silent.config)
          .consentStep,
      isTrue,
    );
  });

  test('untouched progress is judged against the opening step', () {
    final onOpening = <String, dynamic>{'step': 'id-type', 'mediaIds': <String, dynamic>{}};
    expect(isUntouchedProgress(onOpening, openingStep: 'id-type'), isTrue);
    expect(isUntouchedProgress(onOpening), isFalse);
    final moved = <String, dynamic>{'step': 'document-capture', 'mediaIds': <String, dynamic>{}};
    expect(isUntouchedProgress(moved, openingStep: 'id-type'), isFalse);
  });
}
