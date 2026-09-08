import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/myaza_button.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/sticky_actions.dart';

// ─── The actions stay reachable however tall the body ────────────────────────
//
// The whole point of StickyActions: a body taller than the viewport (a map
// that owns every touch, plus the rows under it) must not push Continue off
// the screen. The test surface is 800x600; the body is far taller than that.

void main() {
  testWidgets('holds the button on screen under a body taller than the viewport',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(
        body: StickyActions(
          body: const SizedBox(height: 2000, child: Placeholder()),
          actions: MyazaButton(label: 'Continue', onPressed: () => pressed++),
        ),
      ),
    ));

    final button = find.widgetWithText(MyazaButton, 'Continue');
    expect(button, findsOneWidget);
    // On screen without any scrolling, and below the scrolled body.
    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(rect.top, greaterThan(400));
    await tester.tap(button);
    expect(pressed, 1);
  });

  testWidgets('the body scrolls beneath the actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(
        body: StickyActions(
          body: const Column(
            children: [
              SizedBox(height: 1500),
              Text('the far end'),
            ],
          ),
          actions: MyazaButton(label: 'Continue', onPressed: () {}),
        ),
      ),
    ));
    expect(find.text('the far end'), findsOneWidget);
    await tester.ensureVisible(find.text('the far end'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('the far end')).bottom, lessThanOrEqualTo(600));
    expect(find.widgetWithText(MyazaButton, 'Continue'), findsOneWidget);
  });
}
