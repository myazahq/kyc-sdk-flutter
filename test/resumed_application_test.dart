import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/resumed_application.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show KYCStep, ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── A committed KYB application resumed before its applicant verified ───────
//
// A customer's phone died between the business submission and their own
// verification (2026-09-28). Reopening walked them through the application
// again and sent it under a NEW request id; the server refuses a second
// application on the session the first one claimed, with "Start or resume this
// business verification session before submitting". The resume now replays the
// parent's request id and starts the applicant at their own capture leg.

class _Api extends KYCApiService {
  _Api({this.resume = true}) : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final bool resume;
  final submitted = <VerifyRequest>[];

  @override
  Future<VerifyResponse> verify(VerifyRequest request) async {
    submitted.add(request);
    return request.business != null
        ? const VerifyResponse(
            verificationId: 'ver_parent', status: 'pending', applicantKeyPersonId: 'kp_applicant')
        : const VerifyResponse(verificationId: 'ver_child', status: 'pending');
  }

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      SessionStartResponse(
        sessionId: 'sess_parent',
        resumed: true,
        // The server resumes a committed application at submission.
        progress: const {
          'step': 'submitted',
          'data': {
            'selectedCountry': 'NG',
            'selectedIdType': 'bvn',
            'idNumber': '22222222222',
            'business': {'registrationNumber': 'RC123', 'product': 'business'},
          },
        },
        applicantKeyPersonId: resume ? 'kp_applicant' : null,
        parentVerificationId: resume ? 'ver_parent' : null,
        parentRequestId: resume ? 'req_parent' : null,
      );

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}
}

(ProviderContainer, _Api) _container({bool resume = true}) {
  final api = _Api(resume: resume);
  final c = ProviderContainer(overrides: [
    kycConfigProvider.overrideWithValue(MyazaKYCConfig(
      apiKey: 'pk_test_stub',
      workflowId: 'wf_kyb',
      userId: 'user_1',
      subjectType: 'business',
      business: WorkflowBusinessConfig.fromJson(const {
        'country': 'NG',
        'applicant': {'verification': true},
      }),
    )),
    kycApiServiceProvider.overrideWithValue(api),
    preloadedServerConfigProvider.overrideWithValue(
      const ServerSdkConfig(status: ServerConfigStatus.ready),
    ),
  ]);
  return (c, api);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('pure rules', () {
    test('reads the three facts, and nothing short of all three', () {
      final r = resumedApplicationFrom(
        applicantKeyPersonId: 'kp_1', parentVerificationId: 'ver_1', parentRequestId: 'req_1');
      expect(r?.requestId, 'req_1');
      expect(r?.verificationId, 'ver_1');
      expect(resumedApplicationFrom(applicantKeyPersonId: 'kp_1', parentVerificationId: 'ver_1'), isNull);
      expect(resumedApplicationFrom(
          applicantKeyPersonId: '', parentVerificationId: 'ver_1', parentRequestId: 'req_1'), isNull);
    });

    test('the business request id replays the parent when resumed, else is new', () {
      const r = ResumedApplication(
          verificationId: 'ver_1', applicantKeyPersonId: 'kp_1', requestId: 'req_1');
      expect(businessRequestId(r, () => 'fresh'), 'req_1');
      expect(businessRequestId(null, () => 'fresh'), 'fresh');
    });

    test('the leg starts after the applicant-role step, never on submission', () {
      expect(applicantLegStart([KYCStep.businessDetails, KYCStep.applicantRole, KYCStep.idType,
        KYCStep.liveness, KYCStep.submitted]), KYCStep.idType);
      expect(applicantLegStart([KYCStep.applicantRole, KYCStep.submitted]), isNull);
      expect(applicantLegStart([KYCStep.businessDetails, KYCStep.submitted]), isNull);
    });
  });

  test('a resumed application starts at the applicant leg and replays the parent request id', () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    await _settle();

    final state = c.read(kYCNotifierProvider);
    expect(state.resumedApplication?.requestId, 'req_parent');
    // Not consent, not the business form: the applicant's own leg.
    expect(state.currentStep, KYCStep.idType);

    await notifier.submitAsync();
    await _settle();

    final business = api.submitted.firstWhere((r) => r.business != null);
    expect(business.toJson()['metadata']['requestId'], 'req_parent');
    // The server answered with the applicant KeyPerson, so the applicant's own
    // verification goes out, linked back to the application.
    final applicant = api.submitted.firstWhere((r) => r.business == null);
    expect(applicant.toJson()['metadata']['userId'], 'kp_applicant');
    // And names the application's session: the server refuses an applicant
    // verification without it (409 applicant_session_required). It was left
    // off, the refusal was swallowed, and reopening resumed at the ID step.
    expect(applicant.toJson()['sessionId'], 'sess_parent');
  });

  test('an ordinary resume still sends a new request id', () async {
    final (c, api) = _container(resume: false);
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    await _settle();
    expect(c.read(kYCNotifierProvider).resumedApplication, isNull);

    await notifier.submitAsync();
    await _settle();
    final business = api.submitted.firstWhere((r) => r.business != null);
    expect(business.toJson()['metadata']['requestId'], isNot('req_parent'));
  });
}
