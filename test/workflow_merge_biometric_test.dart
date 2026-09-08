import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// The biometric block rides the workflow merge PER FIELD, like appearance: a
// flow that only switches the review on must not wipe a host's hidden Done.
void main() {
  const base = MyazaKYCConfig(
    apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    country: 'NG',
    biometric: BiometricFlowConfig(doneButton: false),
  );

  test('a flow key wins per field and the host fills the gaps', () {
    final flow = WorkflowFlowConfig.fromJson({
      'scope': 'biometric-authentication',
      'biometric': {'selfieReview': true},
    });
    final merged = mergeWorkflowIntoConfig(base, flow);
    expect(merged.biometric?.selfieReview, isTrue);
    expect(merged.biometric?.doneButton, isFalse);
    expect(merged.showsSelfieReviewOption, isTrue);
    expect(merged.showsDoneButtonOption, isFalse);
  });

  test("a flow's screen copy rides the merge and fills from the host userData", () {
    final flow = WorkflowFlowConfig.fromJson({
      'scope': 'biometric-authentication',
      'biometric': {
        'copy': {
          'waiting': {'title': 'One moment, {firstName}'},
        },
      },
    });
    const host = MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      userData: UserData(firstName: 'Ada'),
      biometric: BiometricFlowConfig(doneButton: false),
    );
    final merged = mergeWorkflowIntoConfig(host, flow);
    expect(merged.biometric?.doneButton, isFalse);
    expect(merged.biometricCopy.waiting?.title, 'One moment, Ada');
  });

  test('a flow without the block leaves the host block alone', () {
    final flow = WorkflowFlowConfig.fromJson({'scope': 'biometric-authentication'});
    final merged = mergeWorkflowIntoConfig(base, flow);
    expect(merged.biometric?.doneButton, isFalse);
    expect(merged.waitsForResultOption, isTrue);
  });

  test('the status response carries the reason code beside the reason', () {
    final r = StatusResponse.fromJson({
      'verificationId': 'ver_1',
      'status': 'declined',
      'reason': 'No match.',
      'reasonCode': 'biometric_auth_failed',
      'createdAt': '2026-09-07T00:00:00Z',
    });
    expect(r.reasonCode, 'biometric_auth_failed');
  });
}
