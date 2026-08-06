import 'dart:async';
import 'dart:ui' show Color;

import 'flash_detector.dart';
import 'flash_liveness_runner.dart';
import 'face_rgb_sampler.dart';

// ─── Flash liveness challenge ─────────────────────────────────────────────────
//
// Binds the pure correlation core (flash_detector) and the sequence runner to a
// live camera: the screen paints a randomized color sequence while the face is
// sampled, and a live face physically reflects those colors in order.
//
// Runs while the liveness VIDEO IS RECORDING, on purpose. The client's verdict
// is only a claim; the server independently re-analyzes the recording against
// the claimed sequence (src/docbio). Flashing outside the recording window would
// leave that check nothing to verify.

/// Default colours per sequence when a workflow doesn't specify one. Four
/// distinct colours give 5×4×3×2 = 120 possible orderings — a stronger
/// anti-spoof than three, at the cost of one extra ~1.1s flash. Orgs override
/// this per flow via `flashSequenceLength`. Kept in step with the web SDK.
const int kFlashSequenceLength = 4;

/// How the workflow's `livenessMode` maps to what actually runs.
extension LivenessModeFlash on String {
  bool get runsFlash => this == 'flash' || this == 'both';
  bool get runsGestures => this != 'flash';
}

/// Runs the sequence and returns the outcome, or null if it couldn't run.
///
/// [isActive] aborts mid-sequence (unmount / retry). A null return is NOT a
/// failure — the caller treats it as "no claim", the same fail-soft posture the
/// detector takes for daylight-washed flashes. Locking a user out because their
/// camera stalled would be worse than accepting a weaker signal, and the server
/// still re-scores the recording.
Future<FlashResult?> runFlashChallenge({
  required List<double>? Function() latestRgb,
  required void Function(Color?) paint,
  required bool Function() isActive,
  List<FlashColor>? sequence,
  FlashTimings timings = const FlashTimings(),
}) async {
  final colors = sequence ?? generateFlashSequence(kFlashSequenceLength);
  final sampler = WindowedRgbSampler(latestRgb);

  final runner = FlashSequenceRunner(
    paint: (color) {
      if (isActive()) paint(color);
    },
    sampleFace: (window) async => isActive() ? sampler.sample(window) : null,
    timings: timings,
  );

  try {
    return await runner.run(colors);
  } catch (_) {
    return null;
  } finally {
    // The overlay is fullscreen and opaque. If anything above threw, leaving it
    // painted would strand the user on a solid red screen.
    paint(null);
  }
}

/// The `integrity.liveness` claim submitted with the verification.
///
/// Shaped for the SERVER's contract (`{ passed, score, inconclusive: bool,
/// sequence }` — src/docbio/rescore.ts), which is also the web SDK's shape.
/// Note `inconclusive` is a BOOLEAN meaning "no flash was measurable at all",
/// while [FlashResult.inconclusive] is a COUNT of unmeasurable flashes. Passing
/// the count straight through would make any single washed-out flash read as
/// "the client reported inconclusive", and the server would then never call a
/// mismatch — quietly disabling the anti-spoof check it exists for.
Map<String, dynamic> livenessIntegrityClaim({
  required String mode,
  FlashResult? flash,
  int faceGlitches = 0,
}) {
  return {
    'mode': mode,
    'faceGlitches': faceGlitches,
    if (flash != null)
      'flash': {
        'passed': flash.passed,
        'score': flash.score,
        'matched': flash.matched,
        'total': flash.total,
        'inconclusive': flash.inconclusive >= flash.total,
        'sequence': flash.sequence,
      },
  };
}
