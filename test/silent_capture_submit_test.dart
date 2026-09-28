import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── Silent capture reaches the wire ─────────────────────────────────────────
//
// Frames upload as `silent_capture`, submit as mediaIds.silentCapture1..3, and
// are described in metadata.device.silentCapture. The flag rides the workflow
// like every template key, with an absent key meaning on.

class _Api extends KYCApiService {
  _Api() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final uploadTypes = <String>[];
  VerifyRequest? submitted;
  var _next = 0;

  @override
  Future<String> upload(Uint8List bytes, String mimeType, String type) async {
    uploadTypes.add('$type:$mimeType');
    return 'med_${++_next}';
  }

  @override
  Future<VerifyResponse> verify(VerifyRequest request) async {
    submitted = request;
    return const VerifyResponse(verificationId: 'ver_1', status: 'pending');
  }

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}
}

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

(ProviderContainer, _Api) _container({bool silentCapture = true, String? scope}) {
  final api = _Api();
  final c = ProviderContainer(overrides: [
    kycConfigProvider.overrideWithValue(MyazaKYCConfig(
      apiKey: 'pk_test_stub',
      country: 'NG',
      scope: scope,
      silentCapture: silentCapture,
      userId: 'user_1',
    )),
    kycApiServiceProvider.overrideWithValue(api),
    preloadedServerConfigProvider.overrideWithValue(
      const ServerSdkConfig(status: ServerConfigStatus.ready),
    ),
  ]);
  return (c, api);
}

/// A passport: a document ID, the flow silent capture belongs to.
IdTypeConfig get _passport => kCuratedIdTypes['NG']!.firstWhere((t) => t.key == 'passport');

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('three frames upload, submit with slots, and a fourth is refused', () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);

    final grabbed = <bool>[];
    for (var i = 0; i < 4; i++) {
      grabbed.add(await notifier.captureSilently(grab: () async => _jpeg, moment: 'document'));
    }
    await _settle();
    expect(grabbed, [true, true, true, false]);
    expect(api.uploadTypes, List.filled(3, 'silent_capture:image/jpeg'));

    notifier.setIdType(_passport);
    await notifier.submitAsync();
    final json = api.submitted!.toJson();
    final mediaIds = json['mediaIds'] as Map<String, dynamic>;
    expect(mediaIds['silentCapture1'], 'med_1');
    expect(mediaIds['silentCapture2'], 'med_2');
    expect(mediaIds['silentCapture3'], 'med_3');
    final device = (json['metadata'] as Map)['device'] as Map;
    final entries = (device['silentCapture'] as List).cast<Map>();
    expect(entries.map((e) => e['slot']), [1, 2, 3]);
    expect(entries.every((e) => e['moment'] == 'document'), isTrue);
    expect(DateTime.tryParse(entries.first['capturedAt'] as String), isNotNull);
  });

  test('a retake keeps the frames already taken; a reset drops them', () async {
    final (c, api) = _container();
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    await notifier.captureSilently(grab: () async => _jpeg, moment: 'document');
    await _settle();

    notifier.setIdType(_passport);
    await notifier.submitAsync();
    expect((api.submitted!.toJson()['mediaIds'] as Map)['silentCapture1'], 'med_1');

    notifier.reset();
    notifier.setIdType(_passport);
    await notifier.submitAsync();
    expect(api.submitted!.toJson()['mediaIds'], isNull);
  });

  test('switched off, or on any scoped flow (none captures a document), nothing is taken', () async {
    for (final (flag, scope) in [(false, null), (true, 'biometric-enrollment'), (true, 'questionnaire')]) {
      final (c, api) = _container(silentCapture: flag, scope: scope);
      addTearDown(c.dispose);
      final notifier = c.read(kYCNotifierProvider.notifier);
      expect(notifier.silentCaptureOn, isFalse);
      expect(await notifier.captureSilently(grab: () async => _jpeg, moment: 'document'), isFalse);
      await _settle();
      expect(api.uploadTypes, isEmpty);
    }
  });

  group('the workflow flag', () {
    const base = MyazaKYCConfig(apiKey: 'pk_test_x');

    test('is on by default and off only when the flow says false', () {
      expect(base.silentCapture, isTrue);
      final absent = mergeWorkflowIntoConfig(base, WorkflowFlowConfig.fromJson(const {}));
      expect(absent.silentCapture, isTrue);
      final off = mergeWorkflowIntoConfig(
        base,
        WorkflowFlowConfig.fromJson(const {'silentCapture': false}),
      );
      expect(off.silentCapture, isFalse);
    });

    test('an absent key keeps a prop that switched it off', () {
      final merged = mergeWorkflowIntoConfig(
        base.copyWith(silentCapture: false),
        WorkflowFlowConfig.fromJson(const {}),
      );
      expect(merged.silentCapture, isFalse);
    });
  });
}
