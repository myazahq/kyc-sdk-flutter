import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_review_card.dart';

// The band under the review map clears the entrance thumbnail hanging over
// it, and on a 360dp phone (the S24, the commonest Android width) that
// clearance left the "Pinned address" pill 8.3px short: a red overflow
// stripe stood on the confirmation screen (user report 2026-09-08). Two
// rules hold it: the clearance is web's exact 128, and the pill's label can
// shrink with an ellipsis, so a larger text scale never draws the stripe
// either.

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        // The step body's own horizontal padding.
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
        ),
      ),
    );

/// A framed entrance with no pin: the thumbnail itself is never built, but
/// the band still clears the space it would hang in.
Widget _card() => AddressReviewCard(
      address: null,
      pin: null,
      isBusiness: false,
      photoPreviewPath: null,
      onEdit: () {},
      streetViewThumb: Uint8List(1),
    );

void main() {
  Future<void> narrow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the band fits a 360dp phone with the entrance hanging over it', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(_host(_card()));
    expect(tester.takeException(), isNull);
    expect(find.text('PINNED ADDRESS'), findsOneWidget);
  });

  testWidgets('a larger text scale shortens the pill rather than overflowing', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(_host(_card(), textScale: 1.6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a business flow fits the same width', (tester) async {
    await narrow(tester);
    await tester.pumpWidget(_host(AddressReviewCard(
      address: null,
      pin: null,
      isBusiness: true,
      photoPreviewPath: null,
      onEdit: () {},
      streetViewThumb: Uint8List(1),
    )));
    expect(tester.takeException(), isNull);
  });
}
