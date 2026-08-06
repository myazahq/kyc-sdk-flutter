import 'dart:math';
import 'dart:ui' show Color;

// ─── Flash liveness (screen-reflection) ───────────────────────────────────────
//
// The screen emits a short RANDOMIZED color sequence while the camera records;
// a live face physically reflects those colors in order. This file is the pure,
// vendor-free correlation core (a direct port of the web SDK's
// liveness/flash-detector.ts): palette + sequence generation + the baseline-vs-
// lit RGB correlation. It has NO camera/native dependency — the caller feeds it
// face-region RGB samples (see FlashSequenceRunner). Defeats replays/injection
// (the sequence didn't exist until the session); bright ambient light makes a
// flash INCONCLUSIVE, which fails soft.

/// One flash color: what the screen paints ([color]) and the RGB channel
/// direction a live reflection should shift along ([boost]).
class FlashColor {
  final String name;
  final Color color;
  final List<double> boost; // unit-ish RGB direction, e.g. red = [1,0,0]

  const FlashColor(this.name, this.color, this.boost);
}

const List<FlashColor> kFlashPalette = [
  FlashColor('red', Color(0xFFFF0000), [1, 0, 0]),
  FlashColor('green', Color(0xFF00FF00), [0, 1, 0]),
  FlashColor('blue', Color(0xFF0000FF), [0, 0, 1]),
  FlashColor('magenta', Color(0xFFFF00FF), [1, 0, 1]),
  FlashColor('cyan', Color(0xFF00FFFF), [0, 1, 1]),
];

/// Minimum shift magnitude (0–255 scale) for a flash to be measurable. Below
/// this the ambient light is too bright to read the reflection ⇒ inconclusive.
const double kMinShiftMagnitude = 3.0;

/// The reflection is "matched" when this fraction of the shift lies along the
/// boosted channel(s).
const double kDominanceThreshold = 0.55;

/// Picks [count] distinct colors from the palette in random order. Pass a [rng]
/// for deterministic tests. The sequence is unknowable in advance — that's the
/// anti-replay property.
List<FlashColor> generateFlashSequence(int count, {Random? rng}) {
  final r = rng ?? Random();
  final pool = List<FlashColor>.from(kFlashPalette)..shuffle(r);
  return pool.take(count.clamp(1, kFlashPalette.length)).toList();
}

/// One flash's outcome.
class FlashSample {
  final bool inconclusive;
  final bool matched;

  /// Dominance of the boosted channel(s) in the shift (0–1); 0 when inconclusive.
  final double score;

  const FlashSample({
    required this.inconclusive,
    required this.matched,
    required this.score,
  });
}

double _dot(List<double> a, List<double> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
double _mag(List<double> v) => sqrt(_dot(v, v));

/// Correlates a single flash: how much the face RGB shifted from [baseline] to
/// [lit], and whether that shift is dominated by the flash's [boost] channels.
/// [baseline]/[lit] are `[r,g,b]` averages (0–255) of the face region.
FlashSample correlateFlash(
  List<double> baseline,
  List<double> lit,
  List<double> boost,
) {
  final shift = [lit[0] - baseline[0], lit[1] - baseline[1], lit[2] - baseline[2]];
  final mag = _mag(shift);
  if (mag < kMinShiftMagnitude) {
    return const FlashSample(inconclusive: true, matched: false, score: 0);
  }
  final boostMag = _mag(boost);
  final boostUnit =
      boostMag == 0 ? boost : [boost[0] / boostMag, boost[1] / boostMag, boost[2] / boostMag];
  // Component of the (positive) shift along the boost direction, normalized.
  final projection = _dot(shift, boostUnit);
  final dominance = (projection / mag).clamp(0.0, 1.0);
  return FlashSample(
    inconclusive: false,
    matched: dominance >= kDominanceThreshold,
    score: dominance.toDouble(),
  );
}

/// The whole-sequence result.
class FlashResult {
  final bool passed;
  final double score;
  final int matched;
  final int total;
  final int inconclusive;
  final List<String> sequence;

  const FlashResult({
    required this.passed,
    required this.score,
    required this.matched,
    required this.total,
    required this.inconclusive,
    required this.sequence,
  });

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'score': score,
        'matched': matched,
        'total': total,
        'inconclusive': inconclusive,
        'sequence': sequence,
      };
}

/// Aggregates per-flash samples into a pass/fail. Passes when either every
/// measurable flash was inconclusive (too-bright daylight — soft pass) or at
/// least ~2/3 of the measurable flashes matched.
FlashResult evaluateFlashSequence(
  List<FlashColor> sequence,
  List<FlashSample> samples,
) {
  final measurable = samples.where((s) => !s.inconclusive).toList();
  final matched = measurable.where((s) => s.matched).length;
  final inconclusive = samples.length - measurable.length;
  final passed = measurable.isEmpty
      ? true // all inconclusive ⇒ ambient too bright ⇒ soft pass
      : matched >= (measurable.length * 0.66).ceil();
  final score = measurable.isEmpty ? 0.0 : matched / measurable.length;
  return FlashResult(
    passed: passed,
    score: score,
    matched: matched,
    total: samples.length,
    inconclusive: inconclusive,
    sequence: sequence.map((c) => c.name).toList(),
  );
}
