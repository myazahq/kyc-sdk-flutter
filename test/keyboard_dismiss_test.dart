import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/kyc_bottom_sheet.dart';

/// iOS's numeric keypad has no done/return key, so a money field could summon
/// a keyboard the user had no way to put away. The sheet now unfocuses on a
/// tap anywhere that isn't itself interactive — this pins that contract.
void main() {
  testWidgets('tapping empty sheet space collapses the keyboard', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KycBottomSheet(
            title: 'A few more questions',
            isFullScreen: true,
            child: Column(
              children: [
                TextField(focusNode: node, keyboardType: TextInputType.number),
                const SizedBox(height: 300),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);

    // A tap on the empty area BELOW the field — not on any control.
    await tester.tapAt(tester.getCenter(find.byType(KycBottomSheet)) + const Offset(0, 120));
    await tester.pump();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('tapping the field itself keeps focus', (tester) async {
    // The dismissal is translucent — interactive children must win their own
    // taps, or every tap into a half-filled input would close the keyboard.
    final node = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KycBottomSheet(
            title: 'A few more questions',
            isFullScreen: true,
            child: TextField(focusNode: node),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
