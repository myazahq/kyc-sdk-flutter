import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/multi_id.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── The multi-ID strip must not flex a scrolling step ───────────────────────
//
// Most steps lay out inside the sheet's scroll view, where height is unbounded.
// The multi-ID wrapper put the step's screen in an Expanded under the position
// strip, which cannot lay out there: a debug build asserted and painted
// nothing, so the ID picker of a multi-ID workflow came up blank on a device
// (2026-09-15). A release build skips the assertion, which is how it shipped.
// This mounts the real flow, so the scroll view the screen sits in is the one
// the SDK builds.

class _StubApi extends KYCApiService {
  _StubApi() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

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

SdkConfigIdType _row(String idType, String label, {required bool document}) =>
    SdkConfigIdType(
      country: 'NG',
      idType: idType,
      label: label,
      requiresDocumentCapture: document,
      scanSides: document ? 'front_only' : null,
      features: const SdkIdTypeFeatures(
        documentVerification: true,
        livenessCheck: true,
        govDbCheck: true,
      ),
    );

void main() {
  testWidgets('the ID picker renders under the multi-ID strip', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const config = MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      consentStep: false,
      multiId: MultiIdConfig(count: 2, minPassed: 2),
    );
    final serverConfig = ServerSdkConfig(
      status: ServerConfigStatus.ready,
      idTypes: [
        _row('bvn', 'Bank Verification Number', document: false),
        _row('nin', 'National Identification Number', document: false),
        _row('passport', 'International Passport', document: true),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kycApiServiceProvider.overrideWithValue(_StubApi()),
        preloadedServerConfigProvider.overrideWithValue(serverConfig),
      ],
      child: const MaterialApp(
        home: Scaffold(body: MyazaKYCWidget(config: config)),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The strip, then the picker beneath it.
    expect(find.text('ID 1'), findsOneWidget);
    expect(find.text('ID 2'), findsOneWidget);
    expect(find.textContaining('Passport'), findsOneWidget);

    // Unmount so the flow's debounce and session work settle inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
