import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_viewfinder.dart';

// ─── Unbounded height ─────────────────────────────────────────────────────────
//
// The document step is rendered inside the sheet's SingleChildScrollView for the
// frames before the immersive flag flips, and a scroll view offers its child
// INFINITE height. A viewfinder that expands unconditionally throws
// "BoxConstraints forces an infinite height" there, and the failure is not
// local: the whole subtree fails to lay out, so the screen comes up broken.
//
// Found on a real iPhone, not in tests — the Android path goes full-screen
// immediately and never passes through the scrolling shell, so the bug was
// invisible on the device it was developed against.

void main() {
  testWidgets('survives being given unbounded height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocumentViewfinder(
              controller: null,
              isLoading: true,
              error: null,
              isBack: false,
              isProcessing: false,
              guideAspect: 1.586,
              hintLabel: 'Passport',
              country: 'NG',
              onCapture: null,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'an unbounded parent must not take the screen down',
    );
  });

  testWidgets('still fills a bounded parent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocumentViewfinder(
            controller: null,
            isLoading: true,
            error: null,
            isBack: false,
            isProcessing: false,
            guideAspect: 1.586,
            hintLabel: 'Passport',
            country: 'NG',
            onCapture: null,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The camera owns the whole screen when it is offered one.
    final size = tester.getSize(find.byType(DocumentViewfinder));
    expect(size.height, tester.view.physicalSize.height / tester.view.devicePixelRatio);
  });
}
