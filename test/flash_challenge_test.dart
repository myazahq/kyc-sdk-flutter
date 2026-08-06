import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_challenge.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_detector.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_liveness_runner.dart';

void main() {
  group('liveness mode', () {
    test('flash and both run the flash sequence; gestures does not', () {
      expect('flash'.runsFlash, isTrue);
      expect('both'.runsFlash, isTrue);
      expect('gestures'.runsFlash, isFalse);
    });

    test('only flash-only mode skips the gesture challenges', () {
      expect('flash'.runsGestures, isFalse);
      expect('both'.runsGestures, isTrue);
      expect('gestures'.runsGestures, isTrue);
    });
  });

  group('integrity claim', () {
    // The server's contract (src/docbio/rescore.ts) reads `inconclusive` as a
    // BOOLEAN meaning "nothing was measurable at all". FlashResult counts the
    // unmeasurable flashes instead, and passing that count straight through
    // would make ONE washed-out flash in three read as a client-reported
    // inconclusive — after which the server never reports a mismatch, silently
    // disabling the anti-spoof check.
    test('inconclusive is true only when NO flash was measurable', () {
      final claim = livenessIntegrityClaim(
        mode: 'flash',
        flash: const FlashResult(
          passed: true, score: 0, matched: 0, total: 3, inconclusive: 3,
          sequence: ['red', 'green', 'blue'],
        ),
      );
      expect((claim['flash'] as Map)['inconclusive'], isTrue);
    });

    test('a single unmeasurable flash does NOT report inconclusive', () {
      final claim = livenessIntegrityClaim(
        mode: 'flash',
        flash: const FlashResult(
          passed: true, score: 1, matched: 2, total: 3, inconclusive: 1,
          sequence: ['red', 'green', 'blue'],
        ),
      );
      expect((claim['flash'] as Map)['inconclusive'], isFalse);
    });

    test('carries the claimed sequence — the server verifies the video against it', () {
      final claim = livenessIntegrityClaim(
        mode: 'both',
        flash: const FlashResult(
          passed: true, score: 1, matched: 2, total: 2, inconclusive: 0,
          sequence: ['magenta', 'cyan'],
        ),
      );
      expect((claim['flash'] as Map)['sequence'], ['magenta', 'cyan']);
      expect(claim['mode'], 'both');
    });

    test('omits flash entirely when it did not run', () {
      expect(livenessIntegrityClaim(mode: 'gestures'), isNot(contains('flash')));
    });
  });

  group('runFlashChallenge', () {
    test('clears the overlay when the sampler throws — never strands a red screen', () async {
      final painted = <Color?>[];
      final result = await runFlashChallenge(
        latestRgb: () => null,
        paint: painted.add,
        isActive: () => true,
        sequence: [kFlashPalette.first],
        timings: FlashTimings.instant,
      );
      // No frames ⇒ inconclusive, not a crash, and the overlay ends neutral.
      expect(result, isNotNull);
      expect(painted.last, isNull);
    });

    test('aborts without painting once inactive', () async {
      final painted = <Color?>[];
      await runFlashChallenge(
        latestRgb: () => null,
        paint: painted.add,
        isActive: () => false,
        sequence: [kFlashPalette.first],
        timings: FlashTimings.instant,
      );
      expect(painted.where((c) => c != null), isEmpty);
    });
  });
}
