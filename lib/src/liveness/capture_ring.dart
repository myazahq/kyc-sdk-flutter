import 'dart:math' as math;

import 'liveness_types.dart';

// The liveness ring's arithmetic — a MIRROR of the web SDK's
// components/CaptureRing.tsx + hooks/useLiveness.ts updateLivenessProgress and
// the React Native SDK's lib/captureRing.ts. Change a rule in one and change it
// in all three in the same commit.
//
// Two numbers. The TARGET is where the test has actually got to and only ever
// moves forward. The DISPLAY eases toward it on real elapsed time, critically
// damped, so a gesture landing (a whole segment in one go) and the detector's
// own frame rate both arrive as motion rather than cuts.

/// Time constant of the display's approach, seconds. ~95% of a gap in three.
const double kRingTau = 0.09;

/// How far a challenge segment may fill on its clock alone: time running out
/// is not progress, so the clock never completes a segment — the gesture
/// landing does.
const double kChallengeSegmentCap = 0.85;

/// The still takes a beat after `capturing` begins; its segment fills across
/// this window. It never CLOSES on it: the clock (and the flash dwell) are
/// capped like a challenge's, and only `complete`, the still in hand, reaches
/// 1. A ring that closed before that announced a photo not yet taken.
const double kCaptureWindowSec = 0.4;

double _clamp01(double n) => n.isNaN ? 0 : n.clamp(0.0, 1.0).toDouble();

double advanceTarget(double target, double real) =>
    math.max(target, _clamp01(real));

double easeToward(double shown, double target, double dt) {
  if (dt <= 0) return shown;
  return shown + (target - shown) * (1 - math.exp(-dt / kRingTau));
}

/// Where the WHOLE test has got to, 0..1, in equal segments: positioning, each
/// step, the capture. Each segment is measured by what actually gates it here.
/// [flashReadyProgress] is the flash-only dwell (0 elsewhere): it is the real
/// measure of the positioning hold and of the pre-flash capture hold, so those
/// segments fill on it rather than on a clock.
///
/// On this SDK `completedCount` IS already bumped at challengePassed: the
/// provider advances the challenge manager before it publishes the count
/// (liveness_provider.dart), so the value at that phase counts the step just
/// passed. Read off the provider, not assumed: the earlier note here claimed
/// the opposite, and the ring landed a segment ahead for the 700 ms of the
/// pass, then snapped back when the next challenge started.
double livenessProgress({
  required LivenessPhase phase,
  required int completedCount,
  required int totalCount,
  required double elapsedInPhase,
  required double challengeTimeout,
  double flashReadyProgress = 0,
}) {
  final seg = 1 / (totalCount + 2);
  switch (phase) {
    case LivenessPhase.positioning:
      return seg * _clamp01(flashReadyProgress);
    case LivenessPhase.challenge:
      final onClock = elapsedInPhase / math.max(challengeTimeout, 1);
      return seg *
          (1 + completedCount + math.min(kChallengeSegmentCap, onClock));
    case LivenessPhase.challengePassed:
      return seg * (1 + completedCount);
    case LivenessPhase.capturing:
      final fill = math.min(
          kChallengeSegmentCap,
          math.max(_clamp01(flashReadyProgress),
              elapsedInPhase / kCaptureWindowSec));
      return seg * (1 + totalCount + fill);
    case LivenessPhase.complete:
      return 1;
    case LivenessPhase.loading:
    case LivenessPhase.failed:
      return 0;
  }
}
