import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/nfc_reader.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/nfc_read_progress.dart';

// The chip read is the one step with no shutter and no preview, and on Android
// no system NFC UI either — so what the user sees IS the progress list. These
// pin the narration: silence during a chip read makes people lift the document,
// which aborts it.

Widget _host(NfcReadStage stage) => MaterialApp(
      home: Scaffold(body: NfcReadProgress(stage: stage)),
    );

void main() {
  group('NfcReadStage labels', () {
    test('every stage has a label', () {
      for (final stage in NfcReadStage.values) {
        expect(stage.label, isNotEmpty, reason: '$stage has no label');
      }
    });
  });

  group('NfcReadProgress', () {
    testWidgets('waiting says what the phone is doing, not nothing',
        (tester) async {
      await tester.pumpWidget(_host(NfcReadStage.waiting));
      expect(find.text(NfcReadStage.waiting.label), findsOneWidget);
    });

    testWidgets('shows every step once the read is under way', (tester) async {
      await tester.pumpWidget(_host(NfcReadStage.readingData));
      expect(find.text(NfcReadStage.authenticating.label), findsOneWidget);
      expect(find.text(NfcReadStage.readingData.label), findsOneWidget);
      expect(find.text(NfcReadStage.readingSecurity.label), findsOneWidget);
      expect(find.text(NfcReadStage.readingPhoto.label), findsOneWidget);
    });

    testWidgets('exactly one step spins at a time', (tester) async {
      await tester.pumpWidget(_host(NfcReadStage.readingSecurity));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('done leaves nothing spinning', (tester) async {
      // The photo group is skipped when the security object didn't come back,
      // so a step left mid-spin after a SUCCESSFUL read would look like failure.
      await tester.pumpWidget(_host(NfcReadStage.done));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
