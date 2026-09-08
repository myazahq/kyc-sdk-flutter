import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/line_skeleton.dart';

// ─── The pending line is a skeleton that speaks ─────────────────────────────
//
// The bar is geometry; the label is the message. The bar must stand at the
// height of the text it replaces (or the card jumps when the words land), it
// must never be a spinner, and the words must still reach a screen reader.
// context.myazaColors falls back to the light scheme without a MyazaTheme.

const _style = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: child),
        ),
      ),
    );

void main() {
  testWidgets('announces its label and draws no spinner', (tester) async {
    await tester.pumpWidget(
      _host(const LineSkeleton(label: 'Finding the address…', style: _style)),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Finding the address…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('stands exactly at the height of the line it replaces',
      (tester) async {
    await tester.pumpWidget(
      _host(const LineSkeleton(label: 'Finding the address…', style: _style)),
    );
    await tester.pump();
    final skeleton = tester.getSize(find.byType(LineSkeleton));

    await tester.pumpWidget(
      _host(const Text('11 Bassey Street', style: _style, maxLines: 1)),
    );
    await tester.pump();
    final line = tester.getSize(find.byType(Text));

    expect(skeleton.height, line.height);
  });

  testWidgets('holds still under reduced motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(
          const LineSkeleton(label: 'Finding the address…', style: _style),
        ),
      ),
    );
    await tester.pump();
    // A repeating pulse would leave the test with a live timer; a static
    // skeleton lets it settle.
    await tester.pumpAndSettle();
    expect(find.byType(LineSkeleton), findsOneWidget);
  });
}
