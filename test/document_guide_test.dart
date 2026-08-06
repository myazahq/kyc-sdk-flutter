import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/document_guide.dart';

// The guide rect is shared by the on-screen overlay and the post-shutter crop.
// If it ever stops fitting the viewfinder, the user frames against a rectangle
// that runs off the preview — which is exactly the bug these pin.

const _card = 1.586;
const _passport = 1.42;

void main() {
  // 440pt-wide phone, viewfinder inset 16pt each side, fixed 300pt tall.
  const viewfinder = Size(408, 300);

  group('documentGuideRect', () {
    test('stays inside the viewfinder for a card', () {
      final r = documentGuideRect(viewfinder, _card);
      expect(r.top, greaterThan(0));
      expect(r.bottom, lessThan(viewfinder.height));
      expect(r.left, greaterThan(0));
      expect(r.right, lessThan(viewfinder.width));
    });

    test('stays inside the viewfinder for a passport', () {
      // The regression: a squarer aspect grew taller from the width-led rule
      // and reached 253pt of 300, top edge 3.6pt from the frame.
      final r = documentGuideRect(viewfinder, _passport);
      expect(r.top, greaterThan(10));
      expect(r.bottom, lessThan(viewfinder.height - 40));
    });

    test('caps height, narrowing the guide rather than overflowing', () {
      final card = documentGuideRect(viewfinder, _card);
      final passport = documentGuideRect(viewfinder, _passport);
      // Both hit the height ceiling, so the squarer document is NARROWER —
      // never taller.
      expect(passport.height, closeTo(card.height, 0.01));
      expect(passport.width, lessThan(card.width));
    });

    test('preserves the document aspect at any size', () {
      for (final aspect in [_card, _passport]) {
        for (final size in [
          const Size(408, 300),
          const Size(320, 300),
          const Size(600, 300),
        ]) {
          final r = documentGuideRect(size, aspect);
          expect(r.width / r.height, closeTo(aspect, 0.001),
              reason: 'aspect drifted at $size');
        }
      }
    });

    test('is width-led on a narrow phone (height cap not reached)', () {
      const narrow = Size(320, 300);
      final r = documentGuideRect(narrow, _card);
      expect(r.width, closeTo(narrow.width * kDocumentGuideWidthFraction, 0.01));
    });

    test('leaves room below for the shutter', () {
      for (final aspect in [_card, _passport]) {
        final r = documentGuideRect(viewfinder, aspect);
        expect(viewfinder.height - r.bottom, greaterThan(45),
            reason: 'shutter would overlap the guide for aspect $aspect');
      }
    });

    test('is horizontally centred', () {
      for (final aspect in [_card, _passport]) {
        final r = documentGuideRect(viewfinder, aspect);
        expect(r.center.dx, closeTo(viewfinder.width / 2, 0.01));
      }
    });
  });
}
