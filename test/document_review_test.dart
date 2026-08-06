import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_review.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_review_side.dart';

// ─── Two-sided review ─────────────────────────────────────────────────────────
//
// The complaint this screen exists to fix: with the sides stacked full-width and
// a retake button under each, the back image and the Continue button both fell
// below the fold on a phone, and people did not realise there was anything left
// to do. So the properties worth pinning are positional — is the second side on
// screen, is the action on screen — not cosmetic.

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

Widget _host(Widget child, {Size size = const Size(390, 640)}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );

DocumentReview _review({
  bool twoSided = true,
  bool isBusy = false,
  VoidCallback? onRetakeBack,
}) =>
    DocumentReview(
      front: _png,
      back: twoSided ? _png : null,
      aspect: 1.586,
      isBusy: isBusy,
      onRetakeFront: () {},
      onRetakeBack: onRetakeBack ?? () {},
      footer: const Text('CONTINUE'),
    );

void main() {
  testWidgets('shows both sides side by side, not stacked', (tester) async {
    await tester.pumpWidget(_host(_review()));
    await tester.pump();

    final front = tester.getRect(find.byKey(kDocumentReviewFrontKey));
    final back = tester.getRect(find.byKey(kDocumentReviewBackKey));

    // Side by side: they share a row rather than one sitting under the other.
    expect(back.left, greaterThan(front.left),
        reason: 'the back side sits beside the front, not below it');
    expect((back.top - front.top).abs(), lessThan(1),
        reason: 'both sides start at the same height');
  });

  testWidgets('the action stays on screen with both sides captured',
      (tester) async {
    // A short phone — the case that produced the original complaint.
    await tester.pumpWidget(_host(_review(), size: const Size(360, 560)));
    await tester.pump();

    final footer = tester.getRect(find.byKey(kDocumentReviewFooterKey));
    expect(footer.bottom, lessThanOrEqualTo(560),
        reason: 'Continue must never require scrolling to find');
    expect(find.text('CONTINUE'), findsOneWidget);
  });

  testWidgets('the action clears the home indicator', (tester) async {
    // The sheet's full-viewport branch pads left/right/top only, so a footer
    // that does not carry its own bottom inset lands ON the home indicator —
    // which is exactly how it first shipped.
    const inset = 34.0; // a modern iPhone's bottom safe area
    tester.view.viewPadding = const FakeViewPadding(bottom: inset * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_review(), size: const Size(390, 800)));
    await tester.pump();

    final footer = tester.getRect(find.byKey(kDocumentReviewFooterKey));
    final button = tester.getRect(find.text('CONTINUE'));
    expect(footer.bottom - button.bottom, greaterThanOrEqualTo(inset),
        reason: 'the button must sit clear of the indicator, not on it');
  });

  testWidgets('says both sides were captured', (tester) async {
    await tester.pumpWidget(_host(_review()));
    await tester.pump();
    expect(find.text('Both sides captured'), findsOneWidget);
  });

  testWidgets('a single-sided document says so and shows one image',
      (tester) async {
    await tester.pumpWidget(_host(_review(twoSided: false)));
    await tester.pump();
    expect(find.text('Photo captured'), findsOneWidget);
    expect(find.byKey(kDocumentReviewBackKey), findsNothing);
  });

  testWidgets('tapping a side enlarges it', (tester) async {
    await tester.pumpWidget(_host(_review()));
    await tester.pump();

    expect(find.byType(DocumentReviewZoom), findsNothing);
    await tester.tap(find.byKey(kDocumentReviewBackKey));
    await tester.pumpAndSettle();

    expect(find.byType(DocumentReviewZoom), findsOneWidget);
    expect(find.text('Retake back'), findsOneWidget);
  });

  testWidgets('retaking from the enlarged view closes it and retakes',
      (tester) async {
    var retookBack = false;
    await tester.pumpWidget(
      _host(_review(onRetakeBack: () => retookBack = true)),
    );
    await tester.pump();

    await tester.tap(find.byKey(kDocumentReviewBackKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake back'));
    await tester.pumpAndSettle();

    expect(retookBack, isTrue);
    expect(find.byType(DocumentReviewZoom), findsNothing,
        reason: 'the enlarged view closes before the camera reopens');
  });

  testWidgets('the enlarged view is opaque and offers a way out',
      (tester) async {
    // It first tinted the theme background at 97% opacity, which on the dark
    // theme is nearly the colour behind it — tapping a photo looked like it did
    // nothing at all.
    await tester.pumpWidget(_host(_review()));
    await tester.pump();
    await tester.tap(find.byKey(kDocumentReviewFrontKey));
    await tester.pumpAndSettle();

    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(DocumentReviewZoom),
        matching: find.byType(ColoredBox),
      ).first,
    );
    expect(box.color.a, greaterThan(0.9),
        reason: 'the overlay must read as a new layer, not a tint');

    // And a close control that is an actual target, not a bare glyph.
    final closeSize = tester.getSize(find.byIcon(LucideIcons.x));
    expect(closeSize.width, greaterThan(0));
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentReviewZoom), findsNothing);
  });

  testWidgets('retake is a labelled button, not a bare icon', (tester) async {
    // An icon-only control on a photo reads as decoration on a phone, where
    // there is no hover to reveal what it does. Both sides must SAY "Retake".
    await tester.pumpWidget(_host(_review()));
    await tester.pump();
    expect(find.text('Retake'), findsNWidgets(2));
  });

  testWidgets('uploading disables retake', (tester) async {
    await tester.pumpWidget(_host(_review(isBusy: true)));
    await tester.pump();

    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(buttons.isNotEmpty, isTrue);
    expect(buttons.every((b) => b.onPressed == null), isTrue,
        reason: 'a retake mid-upload would race the upload it is replacing');
  });

  testWidgets('the images sit at the top, not floating mid-screen',
      (tester) async {
    await tester.pumpWidget(_host(_review(), size: const Size(390, 900)));
    await tester.pump();

    final front = tester.getRect(find.byKey(kDocumentReviewFrontKey));
    expect(front.top, lessThan(250),
        reason: 'the photos are what the user checks first');
  });
}
