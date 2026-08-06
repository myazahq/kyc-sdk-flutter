import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── "You're about to scan your ID" ───────────────────────────────────────────
//
// The document step used to sit inside the sheet's own scroll view, so a tall
// primer simply scrolled with everything else. Making the step FILL THE
// VIEWPORT — so the camera can own the screen — removed that outer scroll view,
// and the primer, which scrolls itself, was left in a bounded Column with no
// Expanded. An unbounded child in a bounded Column overflows instead of
// scrolling, so on a short phone the content was cut off with no way to reach
// it. Reported on a Galaxy S24.
//
// What is pinned here is the COMPOSITION, not the primer's content: any
// self-scrolling child the step places in that Column needs to be Expanded.
// The real ReadyPrimer is not used because its pulse ring animates forever and
// the resulting pending timer says nothing about layout.

/// Stands in for any self-scrolling step child (the ready primer, the camera
/// permission views) — a scroll view whose content exceeds the viewport.
Widget _selfScrollingChild() => SingleChildScrollView(
      child: Column(
        children: [
          for (var i = 0; i < 12; i++)
            const SizedBox(height: 80, child: Placeholder()),
        ],
      ),
    );

Widget _host(Widget child, {Size size = const Size(360, 560)}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );

/// How the document step composes it: a fixed header, then the child.
Widget _stepLayout({required bool expanded}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40, child: ColoredBox(color: Colors.amber)),
        const SizedBox(height: 16),
        if (expanded)
          Expanded(child: _selfScrollingChild())
        else
          _selfScrollingChild(),
      ],
    );

void main() {
  testWidgets('a self-scrolling child fits and scrolls when Expanded',
      (tester) async {
    await tester.pumpWidget(_host(_stepLayout(expanded: true)));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'the step must not overflow');

    // Scrollable in fact, not merely clipped.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('without Expanded it overflows — the shape that shipped',
      (tester) async {
    await tester.pumpWidget(_host(_stepLayout(expanded: false)));
    await tester.pump();

    expect(tester.takeException(), isNotNull,
        reason: 'this is the layout the user could not scroll');
  });

  testWidgets('a tall screen is unaffected either way', (tester) async {
    await tester.pumpWidget(
      _host(_stepLayout(expanded: true), size: const Size(390, 1200)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
