import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/trust_attribution.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/consent_legal_notice.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/powered_by.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/powered_by_custom.dart';

// ─── Footer attribution and the consent notice's Myaza line ───────────────────
//
// The server resolves `branding.trustAttribution` from the published workflow.
// Myaza is the default and what an older server that sends nothing means; a
// custom attribution draws the org's logo instead and never falls back to
// Myaza. Ports the web SDK's trust-attribution and PoweredBy tests.

void main() {
  group('parsing', () {
    test('missing, malformed or non-custom is Myaza', () {
      for (final raw in [null, 'custom', 3, <String, dynamic>{}, {'mode': 'myaza'}, {'mode': 'other'}]) {
        expect(SdkTrustAttribution.fromJson(raw).isCustom, isFalse, reason: '$raw');
      }
    });

    test('custom keeps its logo, dark logo and name, trimmed', () {
      final a = SdkTrustAttribution.fromJson({
        'mode': 'custom',
        'logo': ' https://x/logo.png ',
        'logoDark': 'https://x/dark.png',
        'companyName': ' Acme ',
      });
      expect(a.isCustom, isTrue);
      expect(a.logo, 'https://x/logo.png');
      expect(a.logoDark, 'https://x/dark.png');
      expect(a.companyName, 'Acme');
    });

    test('a custom block with a bad logo stays custom', () {
      final a = SdkTrustAttribution.fromJson({'mode': 'custom', 'logo': 42});
      expect(a.isCustom, isTrue);
      expect(a.logo, isNull);
    });

    test('rides the config branding, and an older server means Myaza', () {
      final old = SdkConfigResponse.fromJson({
        'environment': 'SANDBOX',
        'idTypes': <dynamic>[],
        'branding': {'companyName': 'Acme'},
      });
      expect(old.branding!.trustAttribution.isCustom, isFalse);
      final custom = SdkConfigResponse.fromJson({
        'environment': 'SANDBOX',
        'idTypes': <dynamic>[],
        'branding': {
          'trustAttribution': {'mode': 'custom', 'logo': 'https://x/l.png'},
        },
      });
      expect(custom.branding!.trustAttribution.logo, 'https://x/l.png');
    });
  });

  group('choosing what to draw', () {
    const custom = SdkTrustAttribution.custom(
      logo: 'https://x/light.png',
      logoDark: 'https://x/dark.png',
      companyName: 'Acme',
    );

    test('the dark logo on a dark flow, the main logo otherwise', () {
      expect(resolveTrustAttribution(custom).logo, 'https://x/light.png');
      expect(resolveTrustAttribution(custom, dark: true).logo, 'https://x/dark.png');
      const noDark = SdkTrustAttribution.custom(logo: 'https://x/light.png');
      expect(resolveTrustAttribution(noDark, dark: true).logo, 'https://x/light.png');
    });

    test('Myaza, or nothing from the server, draws the lockup', () {
      expect(resolveTrustAttribution(null).custom, isFalse);
      expect(resolveTrustAttribution(const SdkTrustAttribution.myaza()).custom, isFalse);
    });

    test('the consent notice names Myaza only when the logo is custom', () {
      expect(needsMyazaDisclosure(null), isFalse);
      expect(needsMyazaDisclosure(const SdkTrustAttribution.myaza()), isFalse);
      expect(needsMyazaDisclosure(custom), isTrue);
    });

    test('the org is the attribution name, then the workflow name, then branding', () {
      expect(myazaProviderName(custom, 'Workflow Co', 'Brand Co'), 'Acme');
      const nameless = SdkTrustAttribution.custom(logo: 'https://x/l.png');
      expect(myazaProviderName(nameless, ' Workflow Co ', 'Brand Co'), 'Workflow Co');
      expect(myazaProviderName(nameless, '  ', 'Brand Co'), 'Brand Co');
      expect(myazaProviderName(nameless, null, null), '');
      // A Myaza attribution's name is never used.
      expect(myazaProviderName(const SdkTrustAttribution.myaza(), null, null), '');
    });

    test('the lead-in names Myaza Trust for the org, or alone', () {
      expect(consentMyazaLead(null), isNull);
      expect(consentMyazaLead(const SdkTrustAttribution.myaza()), isNull);
      expect(consentMyazaLead(custom), 'Verification is processed by Myaza Trust for Acme.');
      expect(
        consentMyazaLead(const SdkTrustAttribution.custom(logo: 'https://x/l.png')),
        'Verification is processed by Myaza Trust.',
      );
      expect(
        consentMyazaLead(const SdkTrustAttribution.custom(),
            workflowCompanyName: 'Workflow Co'),
        'Verification is processed by Myaza Trust for Workflow Co.',
      );
    });
  });

  group('the footer', () {
    Widget host(Widget child) => MaterialApp(
          theme: ThemeData(extensions: const [MyazaColorScheme.light]),
          home: Scaffold(body: child),
        );

    testWidgets('Myaza mode is unchanged: "Powered by" and the lockup', (tester) async {
      await tester.pumpWidget(host(const PoweredBy()));
      expect(find.text('Powered by'), findsOneWidget);
      expect(find.text('TRUST'), findsOneWidget);
      expect(find.byType(CustomTrustMark), findsNothing);
    });

    testWidgets('custom mode: "Protected by" and the org logo, no Myaza mark', (tester) async {
      await tester.pumpWidget(host(const PoweredBy(
        attribution: SdkTrustAttribution.custom(
          logo: 'https://x/light.png',
          logoDark: 'https://x/dark.png',
          companyName: 'Acme',
        ),
      )));
      expect(find.text('Protected by'), findsOneWidget);
      expect(find.text('TRUST'), findsNothing);
      expect(find.text('Powered by'), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://x/light.png');
      expect(image.height, CustomTrustMark.logoHeight);
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('a dark flow draws the dark logo', (tester) async {
      await tester.pumpWidget(host(const PoweredBy(
        dark: true,
        attribution: SdkTrustAttribution.custom(
          logo: 'https://x/light.png',
          logoDark: 'https://x/dark.png',
        ),
      )));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://x/dark.png');
    });

    testWidgets('a logo that fails falls back to the org name, never to Myaza', (tester) async {
      await tester.pumpWidget(host(const PoweredBy(
        attribution: SdkTrustAttribution.custom(
          logo: 'https://x/broken.png',
          companyName: 'Acme',
        ),
      )));
      // Network images fail in widget tests (HTTP is blocked), which is the
      // failure this pins.
      await tester.pumpAndSettle();
      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('TRUST'), findsNothing);
    });

    testWidgets('no logo: the org name', (tester) async {
      await tester.pumpWidget(host(const PoweredBy(
        attribution: SdkTrustAttribution.custom(companyName: 'Acme'),
      )));
      expect(find.text('Acme'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
