import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/staggered_reveal.dart';

// Regression: the reveal gated its start on "the reduce-motion setting
// CHANGED". Reduce-motion is off for almost everyone, so that guard was false
// on first build, forward() never ran, and the controller stayed at 0 — which
// for a fade-in renders every child at opacity 0. The screen looked unchanged
// because it was invisible.

Widget _host(Widget child, {bool disableAnimations = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    );

double _opacityOf(WidgetTester tester, String text) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(of: find.text(text), matching: find.byType(Opacity))
        .first,
  );
  return opacity.opacity;
}

void main() {
  testWidgets('children end up fully visible with motion enabled',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      children: [Text('alpha'), Text('beta')],
    )));

    // Mid-flight it is still animating…
    await tester.pump(const Duration(milliseconds: 16));
    // …and settles fully opaque rather than stalling at 0.
    await tester.pumpAndSettle();

    expect(_opacityOf(tester, 'alpha'), 1.0);
    expect(_opacityOf(tester, 'beta'), 1.0);
  });

  testWidgets('does not stay invisible on the very first frame batch',
      (tester) async {
    await tester.pumpWidget(_host(const StaggeredReveal(
      children: [Text('alpha')],
    )));
    // The exact bug: without forward(), this stayed 0 forever.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacityOf(tester, 'alpha'), greaterThan(0.0));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion renders the final state immediately',
      (tester) async {
    await tester.pumpWidget(_host(
      const StaggeredReveal(children: [Text('alpha')]),
      disableAnimations: true,
    ));
    // No pumping past the first frame: it must already be at rest.
    expect(_opacityOf(tester, 'alpha'), 1.0);
  });
}
