import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_provider.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/screens/consent_screen.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── The consent screen: custom texts and the Myaza line ─────────────────────
//
// A workflow's custom copy reaches the screen (and only where a key is
// customisable), the older consent.title still wins, and the notice names
// Myaza Trust as the provider exactly when the footer carries the org's own
// logo. With the Myaza footer the notice reads as it always did.

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

Widget _host(MyazaKYCConfig config, {SdkConfigBranding? branding}) => ProviderScope(
      overrides: [
        kycConfigProvider.overrideWithValue(config),
        kycApiServiceProvider.overrideWithValue(_StubApi()),
        preloadedServerConfigProvider.overrideWithValue(
          ServerSdkConfig(status: ServerConfigStatus.ready, branding: branding),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [MyazaColorScheme.light]),
        home: const Scaffold(body: SingleChildScrollView(child: ConsentScreen())),
      ),
    );

MyazaKYCConfig _config({
  WorkflowTexts? texts,
  String? language,
  KYCConsentContent? consent,
  String subjectType = 'individual',
}) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      workflowId: 'wf_test',
      texts: texts,
      language: language,
      consent: consent,
      subjectType: subjectType,
    );

String _notice(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .firstWhere((s) => s.contains('By tapping Continue'));

void main() {
  testWidgets('with no workflow copy the screen reads as it always did', (tester) async {
    await tester.pumpWidget(_host(_config()));
    await tester.pump();
    expect(find.text('Identity Verification'), findsOneWidget);
    expect(find.text('DURING THIS PROCESS WE WILL'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(
      _notice(tester),
      startsWith('By tapping Continue, you agree to the End User Terms and Privacy Policy'),
    );
  });

  testWidgets('a workflow rewords the customisable texts, in its language', (tester) async {
    await tester.pumpWidget(_host(_config(
      language: 'fr',
      texts: const {
        'en': {'welcome.title': 'Welcome aboard', 'common.continue': 'Next'},
        'fr': {'common.continue': 'Continuer', 'welcome.process.heading': 'Étapes'},
      },
    )));
    await tester.pump();
    expect(find.text('Welcome aboard'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('ÉTAPES'), findsOneWidget);
  });

  testWidgets('the older consent.title still wins over English copy', (tester) async {
    await tester.pumpWidget(_host(_config(
      consent: const KYCConsentContent(title: 'Hi there'),
      texts: const {'en': {'welcome.title': 'Welcome aboard'}},
    )));
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('Welcome aboard'), findsNothing);
  });

  testWidgets('a custom footer logo names Myaza Trust for the org', (tester) async {
    await tester.pumpWidget(_host(
      _config(),
      branding: const SdkConfigBranding(
        companyName: 'Brand Co',
        trustAttribution: SdkTrustAttribution.custom(
          logo: 'https://x/l.png',
          companyName: 'Acme',
        ),
      ),
    ));
    await tester.pump();
    final notice = _notice(tester);
    expect(
      notice,
      startsWith('Verification is processed by Myaza Trust for Acme. By tapping '
          'Continue, you agree to Myaza Trust’s End User Terms and Privacy Policy, '
          'and consent to your personal data being processed to verify your identity.'),
    );
    expect(notice, endsWith('This includes facial recognition and recording this session.'));
  });

  testWidgets('with no org name known, Myaza Trust alone, business wording', (tester) async {
    await tester.pumpWidget(_host(
      _config(subjectType: 'business'),
      branding: const SdkConfigBranding(
        trustAttribution: SdkTrustAttribution.custom(logo: 'https://x/l.png'),
      ),
    ));
    await tester.pump();
    expect(
      _notice(tester),
      startsWith('Verification is processed by Myaza Trust. By tapping Continue, you agree '
          'to Myaza Trust’s End User Terms and Privacy Policy, and consent to your '
          'business and personal data being processed'),
    );
  });

  testWidgets('a Myaza footer keeps the notice as it was', (tester) async {
    await tester.pumpWidget(_host(
      _config(),
      branding: const SdkConfigBranding(companyName: 'Brand Co'),
    ));
    await tester.pump();
    final notice = _notice(tester);
    expect(notice, isNot(contains('processed by Myaza Trust')));
    expect(notice, isNot(contains('Myaza Trust’s')));
  });
}
