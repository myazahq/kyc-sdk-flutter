/// Which step circles to draw, and when to start collapsing them.
///
/// A KYB flow can reach FOURTEEN steps (consent → email → phone →
/// business-details → key-people → documents → applicant-role → country-select →
/// id-type → document-capture → nfc → liveness → questionnaire → submitted), and
/// an individual flow eleven. The circles are a fixed size, so they cannot
/// shrink to fit: on a 360dp Android with 16dp padding, ten steps leave 14dp
/// TOTAL for nine connectors, and twelve steps overflow the row outright.
///
/// COLLAPSING IS A LAST RESORT. The row fits as many real circles as the
/// measured width allows and only windows once they would stop looking like a
/// connected chain — which is what [kMinConnector] decides. A fixed cap would
/// collapse a 9-step flow on a large phone that had room for all of it.
///
/// When it does window, two rules keep the elision honest:
///
///   • The LAST step is always shown. Without it the ellipsis hides how much is
///     left, which is the one thing a progress indicator exists to answer.
///   • The FIRST step is always shown, so the row still reads as a whole
///     journey rather than a fragment floating in the middle.
///
///     1 ··· 5 6 7 ··· 10
///
/// Ported from the React Native SDK's lib/step-window.ts — keep the two in step.
library;

/// A rendered slot: a step index, or a collapsed run of them.
///
/// Dart has no union type, so the ellipsis is a sentinel index. It is negative
/// so it can never collide with a real step.
const int kStepEllipsis = -1;

/// Shortest connector that still reads as a line joining two circles rather
/// than a stray dash. Below this the "chain" metaphor is gone and the row just
/// looks cramped.
const double kMinConnector = 10;

/// Horizontal margin a connector carries on each side (matches the widget).
const double _connectorMargin = 6;

/// Never collapse below this many circles. At 5 the pattern still reads as
/// first · gap · current · gap · last; below it the row says nothing useful.
const int _minCircles = 5;

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// How many circles fit across [width] before they stop looking like a chain.
///
///   n·size + (n−1)·(margins + minConnector) ≤ width
///
/// Returns 0 when the width is not known yet, which the caller reads as "render
/// them all" — an un-measured first frame should not flash a collapsed row.
int fitStepCircles(double width, double circleSize) {
  if (!width.isFinite || width <= 0) return 0;
  const gap = _connectorMargin + kMinConnector;
  final n = ((width + gap) / (circleSize + gap)).floor();
  return n < 1 ? 1 : n;
}

/// Slots to render, left to right.
///
/// [active] is the 0-based index of the current step. [maxCircles] comes from
/// [fitStepCircles]; 0 means "unknown, render everything".
List<int> windowedSteps(int total, int active, {int maxCircles = 0}) {
  if (total <= 0) return const [];
  final all = List<int>.generate(total, (i) => i);
  if (maxCircles <= 0 || total <= maxCircles) return all;

  // A collapsed row also pays for up to TWO ellipses, each about as wide as a
  // circle once its padding and connectors are counted.
  final budget = maxCircles - 2 < _minCircles ? _minCircles : maxCircles - 2;
  if (total <= budget) return all;

  const first = 0;
  final last = total - 1;
  final current = _clamp(active, first, last);

  // First and last are drawn unconditionally; the rest of the budget is a
  // window centred on the current step.
  final windowSize = budget - 2 < 1 ? 1 : budget - 2;
  final half = ((windowSize - 1) / 2).floor();
  final start = _clamp(
    current - half,
    first + 1,
    (last - windowSize) < (first + 1) ? first + 1 : last - windowSize,
  );
  final end = (start + windowSize - 1) > (last - 1) ? last - 1 : start + windowSize - 1;

  final slots = <int>[first];
  if (start > first + 1) slots.add(kStepEllipsis);
  for (var i = start; i <= end; i++) {
    slots.add(i);
  }
  if (end < last - 1) slots.add(kStepEllipsis);
  slots.add(last);
  return slots;
}
