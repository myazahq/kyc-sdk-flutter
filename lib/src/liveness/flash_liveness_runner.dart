import 'dart:async';
import 'dart:ui' show Color;

import 'flash_detector.dart';

// ─── Flash sequence runner ────────────────────────────────────────────────────
//
// Orchestrates a flash-liveness challenge: for each color it paints neutral,
// samples the baseline face RGB, paints the color, samples the lit face RGB, and
// correlates. It is deliberately decoupled from the camera:
//
//   • [FlashPainter]  — the UI paints a fullscreen color (null = neutral). Wired
//     to a ValueNotifier the liveness overlay watches.
//   • [FaceRgbSampler] — returns the face-region average `[r,g,b]` (0–255) from
//     the current camera frame, or null if no face. THIS is the native
//     integration seam: on device it reads the camera frame stream (Apple Vision
//     / CameraX), which is why it's injected rather than implemented here.
//
// The timings + correlation match the web SDK; this runner is unit-testable with
// a scripted sampler and zeroed timings (no camera, no native).

typedef FlashPainter = void Function(Color? color);

/// Returns the face-region average `[r,g,b]` (0–255) AVERAGED OVER [window], or
/// null if no frame was readable.
///
/// The window is the point: a single frame's sensor noise and auto-exposure
/// drift are the same order as a real flash's reflection, so a one-shot sample
/// correlates poorly. The web SDK averages ~15 samples/sec across the same
/// windows (300ms baseline, 450ms lit).
typedef FaceRgbSampler = Future<List<double>?> Function(Duration window);

/// Tunable per-flash timings (defaults mirror the web detector). Tests pass
/// [FlashTimings.instant] to run without real delays.
///
/// `baselineSettle` / `litSettle` are the sampling WINDOWS handed to the
/// sampler, not dead time either side of a one-shot read — matching the web's
/// 300ms/450ms averaging windows.
class FlashTimings {
  final Duration neutralHold;
  final Duration baselineSettle;
  final Duration litLatency;
  final Duration litSettle;

  const FlashTimings({
    this.neutralHold = const Duration(milliseconds: 150),
    this.baselineSettle = const Duration(milliseconds: 300),
    this.litLatency = const Duration(milliseconds: 200),
    this.litSettle = const Duration(milliseconds: 450),
  });

  static const instant = FlashTimings(
    neutralHold: Duration.zero,
    baselineSettle: Duration.zero,
    litLatency: Duration.zero,
    litSettle: Duration.zero,
  );
}

class FlashSequenceRunner {
  final FlashPainter paint;
  final FaceRgbSampler sampleFace;
  final FlashTimings timings;

  const FlashSequenceRunner({
    required this.paint,
    required this.sampleFace,
    this.timings = const FlashTimings(),
  });

  /// Runs the full [sequence], returning the aggregated [FlashResult]. A flash
  /// whose baseline/lit sample is missing (no face) is treated as inconclusive.
  Future<FlashResult> run(List<FlashColor> sequence) async {
    final samples = <FlashSample>[];
    for (final flash in sequence) {
      // Neutral baseline immediately before each flash, so ambient drift is
      // tracked per-flash rather than assumed constant across the sequence.
      paint(null);
      await Future<void>.delayed(timings.neutralHold);
      final baseline = await sampleFace(timings.baselineSettle);

      paint(flash.color);
      // Screen paint + camera exposure both lag; sampling immediately would
      // average the pre-flash frames back in.
      await Future<void>.delayed(timings.litLatency);
      final lit = await sampleFace(timings.litSettle);

      if (baseline == null || lit == null) {
        samples.add(
          const FlashSample(inconclusive: true, matched: false, score: 0),
        );
      } else {
        samples.add(correlateFlash(baseline, lit, flash.boost));
      }
    }
    paint(null); // restore neutral
    return evaluateFlashSequence(sequence, samples);
  }
}
