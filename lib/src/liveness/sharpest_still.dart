import 'dart:typed_data';

import '../utils/selfie_sharpness.dart';

// ─── The sharpest of a few photos, and a quiet second try ────────────────────
//
// The selfie used to be whichever frame came last, and a soft one was left to
// the review screen: a notice, and a person deciding whether to retake. With
// the review off by default nobody is there to decide, so the SDK does.
//
//   1. Several photos are taken a moment apart and the sharpest is kept. Most
//      soft selfies are one unlucky frame; this prevents them.
//   2. If even the sharpest is soft, the SDK asks the person to hold still and
//      takes them again, by itself, at most [kSoftRetakes] times.
//   3. If it is still soft after that, the best one is kept and the review
//      screen is shown with its notice. The sharpness floor was never
//      calibrated on real phones, so it may not be allowed to trap anybody:
//      a smudged lens ends in a screen with Continue on it, not in a loop.

/// Photos per attempt.
const int kStillBurst = 3;

/// Between two photos of one attempt: long enough for a new camera frame.
const Duration kStillBurstGap = Duration(milliseconds: 90);

/// Automatic retakes after a soft first attempt.
const int kSoftRetakes = 2;

const String kRetakeInstruction = 'Hold still, taking that again';

class ScoredStill {
  const ScoredStill(this.bytes, this.score);

  final Uint8List bytes;

  /// Laplacian variance of the face region, or null when it could not be
  /// measured. Unmeasured is unknown, never soft.
  final double? score;

  bool get soft => isSelfieBlurry(score);
}

/// The sharpest of [stills]: the highest measured score, and when none could
/// be measured, the most recent. Null for an empty list.
ScoredStill? sharpestOf(List<ScoredStill> stills) {
  ScoredStill? best;
  for (final still in stills) {
    final score = still.score;
    if (best == null) {
      best = still;
    } else if (score == null) {
      // Unmeasured only ever replaces another unmeasured one.
      if (best.score == null) best = still;
    } else if (best.score == null || score > best.score!) {
      best = still;
    }
  }
  return best;
}
