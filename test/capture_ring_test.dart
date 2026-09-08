import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/capture_ring.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/liveness_types.dart';

// Mirror of the web and React Native ring tests. Two numbers: a target that
// only moves forward, a display that eases toward it.
void main() {
  const frame = 1 / 60;

  group('advanceTarget', () {
    test('never goes backwards, however far the real number falls', () {
      for (final real in [0.6, 0.4, 0.2, 0.0, double.nan]) {
        expect(advanceTarget(0.7, real), 0.7);
      }
    });
    test('follows real progress exactly and clamps an overshoot', () {
      expect(advanceTarget(0.2, 0.5), 0.5);
      expect(advanceTarget(0.9, 16 / 15), 1.0);
    });
  });

  group('easeToward', () {
    test('never overshoots', () {
      var shown = 0.0;
      for (var i = 0; i < 120; i++) {
        final next = easeToward(shown, 0.5, frame);
        expect(next, greaterThanOrEqualTo(shown));
        expect(next, lessThanOrEqualTo(0.5));
        shown = next;
      }
    });
    test('is frame-rate independent', () {
      final whole = easeToward(0, 1, frame);
      final halves = easeToward(easeToward(0, 1, frame / 2), 1, frame / 2);
      expect(halves, closeTo(whole, 1e-10));
    });
    test('closes fast enough to land with the shutter', () {
      var shown = 0.0;
      for (var t = 0.0; t < 0.3; t += frame) {
        shown = easeToward(shown, 1, frame);
      }
      expect(shown, greaterThan(0.95));
    });
  });

  group('livenessProgress', () {
    const seg = 1 / 4; // positioning + 2 steps + capture
    double at(LivenessPhase phase,
            {int completed = 0, double elapsed = 0, double dwell = 0}) =>
        livenessProgress(
          phase: phase,
          completedCount: completed,
          totalCount: 2,
          elapsedInPhase: elapsed,
          challengeTimeout: 8,
          flashReadyProgress: dwell,
        );

    test('is empty before the test has moved', () {
      expect(at(LivenessPhase.loading), 0);
      expect(at(LivenessPhase.positioning), 0);
    });

    test('the positioning hold fills on the flash dwell, the real measure', () {
      expect(
          at(LivenessPhase.positioning, dwell: 0.5), closeTo(seg * 0.5, 1e-10));
    });

    test('fills a challenge on its clock but never completes it that way', () {
      final early = at(LivenessPhase.challenge, elapsed: 1);
      final late = at(LivenessPhase.challenge, elapsed: 60);
      expect(early, greaterThan(seg));
      expect(early, lessThan(late));
      expect(late, closeTo(seg * (1 + kChallengeSegmentCap), 1e-10));
    });

    test('a passed gesture lands EXACTLY on the start of the next segment', () {
      // The provider publishes completedCount already advanced at
      // challengePassed, so the first pass reads completed: 1 and must land
      // on the first step's full segment. A `contains` over both readings
      // used to hedge this, which is how a one-segment overshoot shipped.
      final passed = at(LivenessPhase.challengePassed, completed: 1);
      expect(passed, closeTo(seg * 2, 1e-10));
      expect(at(LivenessPhase.challengePassed, completed: 2),
          closeTo(seg * 3, 1e-10));
    });

    test('the next challenge does not move the ring backwards', () {
      final passed = at(LivenessPhase.challengePassed, completed: 1);
      final nextStart = at(LivenessPhase.challenge, completed: 1, elapsed: 0);
      expect(nextStart, closeTo(passed, 1e-10));
      expect(at(LivenessPhase.challenge, completed: 1, elapsed: 1),
          greaterThan(passed));
    });

    test(
        'the capture segment fills across the still but only complete closes the ring',
        () {
      // The still is not in hand until `complete`. A clock or dwell that
      // closed the ring showed a finished circle before the shutter.
      expect(
          at(LivenessPhase.capturing, completed: 2), closeTo(seg * 3, 1e-10));
      expect(at(LivenessPhase.capturing, completed: 2, elapsed: 5),
          closeTo(seg * (3 + kChallengeSegmentCap), 1e-10));
      expect(at(LivenessPhase.capturing, completed: 2, elapsed: 5),
          lessThan(1));
      expect(at(LivenessPhase.capturing, completed: 2, dwell: 0.5),
          closeTo(seg * 3.5, 1e-10));
      expect(at(LivenessPhase.capturing, completed: 2, dwell: 1.0),
          closeTo(seg * (3 + kChallengeSegmentCap), 1e-10));
      expect(at(LivenessPhase.complete), 1);
    });
  });
}
