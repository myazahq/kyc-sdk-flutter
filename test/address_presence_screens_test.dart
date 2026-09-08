import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_intro_disclosures.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_intro_gate.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/presence_blocks.dart';

// ─── What the applicant is told about presence ───────────────────────────────
//
// The primer explains, the disclosures are the consent artefact, and the
// success card says the check is already running. The wording is a CROSS-SDK
// MIRROR of the web and RN SDKs. Split from address_screens_test.dart
// (200-line rule), which keeps the capture screens.

/// The test surface is 800x600 whatever a SizedBox says, so the host scrolls
/// rather than pretending to be a tall phone: anything below the fold is
/// reached with `ensureVisible`, the way a person reaches it by scrolling.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('the presence primer', () {
    testWidgets('states the promise and the three milestones', (tester) async {
      await tester.pumpWidget(
          _host(AddressIntroGate(onAcknowledge: () {})));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Address verification'.toUpperCase()), findsOneWidget);
      expect(find.text('Let’s confirm your address'), findsOneWidget);
      expect(find.text('Pin your address'), findsOneWidget);
      expect(find.text('Quiet check-ins'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Got it, let’s go'), findsOneWidget);
    });

    testWidgets('acknowledging is what dismisses it', (tester) async {
      var seen = false;
      await tester.pumpWidget(
          _host(AddressIntroGate(onAcknowledge: () => seen = true)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Got it, let’s go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it, let’s go'));
      expect(seen, isTrue);
    });
  });

  group('the disclosures', () {
    testWidgets('open one at a time, and start closed', (tester) async {
      await tester.pumpWidget(_host(const AddressIntroDisclosures()));
      // The bodies are the consent artefact: present but collapsed, so nothing
      // is claimed to have been read before it was opened.
      expect(find.textContaining('Only day-level summaries'), findsNothing);

      await tester.tap(find.text('How it works'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Only day-level summaries'), findsOneWidget);

      await tester.tap(find.text('You stay in control'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Only day-level summaries'), findsNothing);
      expect(find.textContaining('turn location off at any time'),
          findsOneWidget);
    });
  });

  group('the success card', () {
    testWidgets('says the check is already running', (tester) async {
      await tester.pumpWidget(_host(const PresenceExpectations()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Address check active'.toUpperCase()), findsOneWidget);
      expect(find.text('Your address confirms itself from here'),
          findsOneWidget);
      expect(find.text('Check started'), findsOneWidget);
      expect(find.text('Nothing else for you to do. Carry on as normal.'),
          findsOneWidget);
      // The pulsing dot never settles, so the frame is disposed rather than
      // waited on.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
