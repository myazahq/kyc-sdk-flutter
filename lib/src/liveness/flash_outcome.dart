import 'flash_detector.dart';

// ─── What to do once a flash (screen-reflection) sequence has run ────────────
//
// An UNMEASURABLE flash used to pass soft: bright light drowns the reflection,
// and so does a phone screen held up to the camera, which lights itself. That
// soft pass is exactly what a replay needs. Now:
//
//   - measured and matched          → pass
//   - measured and NOT matched      → fail
//   - unmeasurable, first time      → retry once, after "move away from bright light"
//   - unmeasurable again, 'both'    → the gestures that ran first carried it
//   - unmeasurable again, 'flash'   → fall back to gesture challenges
//
// Port of the web SDK's liveness/flash-outcome.ts and the React Native SDK's
// liveness/flashOutcome.ts. Change all three together.

enum FlashOutcome { pass, retry, acceptGestures, fallbackGestures, fail }

const int kFlashInconclusiveRetries = 1;

const String kFlashRetryGuidance = 'Move away from bright light and hold still';

/// No flash in the run could be measured. A sequence that could not run at all
/// (a null result) counts as unmeasurable, never as passed.
bool flashUnmeasurable(FlashResult? result) =>
    result == null || result.total - result.inconclusive <= 0;

FlashOutcome flashOutcome({
  required FlashResult? result,
  required String mode,
  required int retriesUsed,
}) {
  if (result != null && result.passed) return FlashOutcome.pass;
  if (!flashUnmeasurable(result)) return FlashOutcome.fail;
  if (retriesUsed < kFlashInconclusiveRetries) return FlashOutcome.retry;
  return mode == 'both'
      ? FlashOutcome.acceptGestures
      : FlashOutcome.fallbackGestures;
}
