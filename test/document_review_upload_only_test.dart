import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/document_capture_methods.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_review.dart';

// ─── Review wording follows the capture mode ─────────────────────────────────
//
// On a flow with the camera off (`allowDocumentScan: false`) the applicant
// picked their photos and never saw a camera, so the review must not say
// "captured" or "Retake". Camera-only and both-on keep today's words exactly.

/// A 1×1 PNG. Image.memory needs real bytes; nothing here inspects the pixels.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Future<void> _pump(
  WidgetTester tester,
  DocumentCaptureMethods methods, {
  bool twoSided = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 390,
        height: 640,
        child: DocumentReview(
          front: _png,
          back: twoSided ? _png : null,
          aspect: 1.586,
          isBusy: false,
          uploadOnly: methods.uploadOnly,
          onRetakeFront: () {},
          onRetakeBack: () {},
          footer: const Text('CONTINUE'),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _zoomFront(WidgetTester tester) async {
  await tester.tap(find.byKey(kDocumentReviewFrontKey));
  await tester.pumpAndSettle();
  expect(find.byKey(kDocumentReviewZoomKey), findsOneWidget);
}

void main() {
  final uploadOnly = documentCaptureMethods(
      allowDocumentScan: false, allowDocumentUpload: true);
  final cameraOnly = documentCaptureMethods(
      allowDocumentScan: true, allowDocumentUpload: false);
  final both = documentCaptureMethods(
      allowDocumentScan: true, allowDocumentUpload: true);

  testWidgets('upload-only says added and Replace, never captured or Retake',
      (tester) async {
    await _pump(tester, uploadOnly);

    expect(find.text('Both sides added'), findsOneWidget);
    expect(find.text('Replace'), findsNWidgets(2));
    expect(find.textContaining('captured'), findsNothing);
    expect(find.textContaining('Retake'), findsNothing);

    await _zoomFront(tester);
    expect(find.widgetWithText(FilledButton, 'Replace'), findsOneWidget);
    expect(find.textContaining('Retake'), findsNothing);
  });

  testWidgets('a single-sided upload says the photo was added', (tester) async {
    await _pump(tester, uploadOnly, twoSided: false);
    expect(find.text('Photo added'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.textContaining('captured'), findsNothing);
  });

  for (final (name, methods) in [('camera-only', cameraOnly), ('both on', both)]) {
    testWidgets('$name keeps the camera wording', (tester) async {
      await _pump(tester, methods);
      expect(find.text('Both sides captured'), findsOneWidget);
      expect(find.text('Retake'), findsNWidgets(2));
      expect(find.textContaining('Replace'), findsNothing);

      await _zoomFront(tester);
      expect(find.widgetWithText(FilledButton, 'Retake front'), findsOneWidget);
    });

    testWidgets('$name single-sided still says captured', (tester) async {
      await _pump(tester, methods, twoSided: false);
      expect(find.text('Photo captured'), findsOneWidget);
    });
  }
}
