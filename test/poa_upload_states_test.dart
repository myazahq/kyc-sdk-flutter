import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/upload_limits.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/proof_of_address_parts.dart';

// The proof-of-address step used to say "Tap to upload an image or PDF" — which
// never told the user WHICH of the offered document kinds to supply, and after
// upload gave no way to remove a wrong file. These pin the two things that fix:
// the drop zone names the document, and the uploaded row is removable.

Widget host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: SizedBox(width: 390, child: child)),
    );

void main() {
  group('drop zone', () {
    testWidgets('names the document kind being asked for', (tester) async {
      await tester.pumpWidget(host(const PoaDropzone(
        uploading: false,
        typeLabel: 'Utility bill',
      )));

      expect(find.text('Upload your utility bill'), findsOneWidget);
      expect(find.text(kUploadHint), findsOneWidget);
    });

    testWidgets('a renamed "other" kind flows through to the call to action',
        (tester) async {
      // An org can rename `other` in the workflow builder; the drop zone has to
      // ask for THAT, not "other document".
      await tester.pumpWidget(host(const PoaDropzone(
        uploading: false,
        typeLabel: 'Council tax letter',
      )));
      expect(find.text('Upload your council tax letter'), findsOneWidget);
    });

    testWidgets('shows progress and blocks taps while uploading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(PoaDropzone(
        uploading: true,
        typeLabel: 'Utility bill',
        onTap: () => taps++,
      )));

      expect(find.text('Uploading…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(PoaDropzone), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0, reason: 'a second pick mid-upload would race the first');
    });
  });

  group('uploaded row', () {
    testWidgets('shows the file name, its kind, and a working remove',
        (tester) async {
      var removed = 0;
      await tester.pumpWidget(host(PoaUploadedRow(
        fileName: 'Screenshot 2026-07-22 at 04.02.49.png',
        typeLabel: 'Utility bill',
        previewBytes: null,
        isPdf: true,
        onRemove: () => removed++,
      )));

      expect(find.text('Screenshot 2026-07-22 at 04.02.49.png'), findsOneWidget);
      expect(find.text('Utility bill'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove document'));
      await tester.pump();
      expect(removed, 1);
    });

    testWidgets('a PDF renders the document tile, not a broken image',
        (tester) async {
      await tester.pumpWidget(host(const PoaUploadedRow(
        fileName: 'statement.pdf',
        typeLabel: 'Bank statement',
        previewBytes: null,
        isPdf: true,
      )));
      expect(find.byType(PoaThumb), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('config labels', () {
    test('otherLabel renames only the "other" kind', () {
      const cfg = ProofOfAddressConfig(
        enabled: true,
        otherLabel: 'Council tax letter',
      );
      expect(cfg.labelFor(PoaDocumentType.other), 'Council tax letter');
      expect(cfg.labelFor(PoaDocumentType.utilityBill), 'Utility bill');
    });

    test('a blank otherLabel falls back to the generic label', () {
      const cfg = ProofOfAddressConfig(enabled: true, otherLabel: '   ');
      expect(cfg.labelFor(PoaDocumentType.other), 'Other document');
    });

    test('otherLabel is parsed off a resolved workflow', () {
      final cfg = ProofOfAddressConfig.fromJson({
        'enabled': true,
        'documentTypes': ['utility_bill'],
        'maxAgeDays': 30,
        'otherLabel': 'Council tax letter',
      });
      expect(cfg.maxAgeDays, 30);
      expect(cfg.offeredTypes, [PoaDocumentType.utilityBill]);
      expect(cfg.otherLabel, 'Council tax letter');
    });
  });
}
