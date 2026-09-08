import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_marker.dart';

// ─── The Bolt pin ────────────────────────────────────────────────────────────
//
// The built-in OSM picker wears the same pin as the framed Google map: 46x65,
// settled with its stem tip on the map centre, lifted 17px with the landing
// dot beneath it while the map pans. The three mirrors share the geometry.

void main() {
  Widget host(bool lifted) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapPinMarker(lifted: lifted, color: const Color(0xFF5645F5)),
          ),
        ),
      );

  testWidgets('is the reference size and hides the dot when settled',
      (tester) async {
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(MapPinMarker));
    expect(size, const Size(kPinWidth, kPinHeight));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset, Offset.zero);
  });

  testWidgets('lifts 17px and shows the landing dot while panning',
      (tester) async {
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      const Offset(0, -kPinLift / kPinHeight),
    );
  });
}
