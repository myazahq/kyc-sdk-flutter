import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/icons/icons.dart';

/// An icon is the size the call site asked for, whatever box it is handed.
///
/// Flutter's `Icon` draws a font glyph, which is a fixed size under any
/// constraints. This draws an SVG, which fills the box it is given, so a
/// `Container` with a fixed width and height (tight constraints, and the SDK is
/// full of them for the round icon chips) silently drew the glyph at the
/// container's size instead. On the consent hero that was a 28 icon rendering
/// at 56, about twice the intended size.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('keeps its size inside a tight container', (tester) async {
    await pump(
      tester,
      Container(
        width: 56,
        height: 56,
        color: const Color(0xFFF4B746),
        child: const MyazaIcon(MyazaIcons.shieldCheck, size: 28),
      ),
    );
    expect(tester.getSize(find.byType(HugeIcon)), const Size(28, 28));
  });

  testWidgets('keeps its size when the parent is loose', (tester) async {
    await pump(tester, const MyazaIcon(MyazaIcons.shieldCheck, size: 28));
    expect(tester.getSize(find.byType(HugeIcon)), const Size(28, 28));
  });

  testWidgets('falls back to the ambient IconTheme size', (tester) async {
    await pump(
      tester,
      const IconTheme(
        data: IconThemeData(size: 18),
        child: SizedBox(width: 56, height: 56, child: MyazaIcon(MyazaIcons.x)),
      ),
    );
    expect(tester.getSize(find.byType(HugeIcon)), const Size(18, 18));
  });
}
