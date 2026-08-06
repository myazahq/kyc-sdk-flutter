// ─── Flash-ready gate ─────────────────────────────────────────────────────────
//
// Decides WHEN a flash-only liveness sequence may start. Pure logic, no camera
// or widget dependency, so the timing is unit-tested rather than tuned on a
// device.
//
// It exists because flash-only mode otherwise flashes the instant a face is at
// a good distance — before lighting is checked and off a single frame. That is
// fine for the gesture flow, whose challenges take seconds and re-check
// framing throughout; flash mode has no such buffer, so the "come closer / more
// light" guidance never has time to show and the flash feels like it jumps out.
//
// Three conditions, each earning its place:
//   • FRAMED   — the face is at the right distance (no position warning).
//   • LIT      — no lighting warning. But "no warning" is ambiguous until the
//     brightness sampler has actually produced a reading (it warms up for ~1.5s,
//     during which lighting is UNKNOWN, not confirmed-good). So the gate needs
//     the lighting to have been positively sampled — otherwise a dim room reads
//     as fine and flashes with no "more light" prompt.
//   • DWELL    — the framed+lit state held steady for a short, visible moment,
//     so a face merely passing through the right distance doesn't trigger, and
//     the guidance + a "hold still" beat land before the screen flashes.

/// How long framed+lit must hold before flashing.
const Duration kFlashReadyDwell = Duration(milliseconds: 1200);

/// Safety valve: if framing is good but the sampler NEVER confirms lighting
/// (sampling unsupported/failing on this device), proceed anyway after this so
/// the user is never stuck on a permanent "hold still". Longer than the dwell
/// AND the sampler's warmup, so a healthy device always confirms lighting first
/// and this never fires in the normal case.
const Duration kFlashLightingWait = Duration(milliseconds: 3000);

/// The gate's verdict for one frame.
class FlashReadyState {
  /// Start the flash now.
  final bool ready;

  /// 0..1 across the dwell — for a subtle "getting ready" indicator. 0 whenever
  /// the hold hasn't started or has just reset.
  final double progress;

  const FlashReadyState({required this.ready, required this.progress});
}

/// Tracks the framed+lit hold across frames. One instance per liveness attempt;
/// call [reset] to reuse it for a retry.
class FlashReadyGate {
  final Duration dwell;
  final Duration lightingWait;

  FlashReadyGate({
    this.dwell = kFlashReadyDwell,
    this.lightingWait = kFlashLightingWait,
  });

  DateTime? _heldSince;

  /// Feed one frame's framing/lighting verdict.
  ///
  /// [framed]        — face at the right distance (no position warning).
  /// [lit]           — no lighting warning (dark/bright). Note this is true
  ///                   while lighting is still UNKNOWN too, which is why
  ///                   [lightingConfirmed] gates separately.
  /// [lightingConfirmed] — the brightness sampler has produced at least one
  ///                   real reading, so [lit] means "measured OK" not "unknown".
  /// [now]           — injected clock (no wall-clock reads in the gate, so tests
  ///                   are deterministic).
  FlashReadyState update({
    required bool framed,
    required bool lit,
    required bool lightingConfirmed,
    required DateTime now,
  }) {
    // Any break in framing or lighting restarts the hold — the whole point is a
    // CONTINUOUS steady moment, not a cumulative one.
    if (!framed || !lit) {
      _heldSince = null;
      return const FlashReadyState(ready: false, progress: 0);
    }

    _heldSince ??= now;
    final held = now.difference(_heldSince!);

    // Wait for a positive lighting reading before counting the dwell as
    // complete — unless the sampler has stayed silent past the safety window,
    // in which case proceed rather than trap the user.
    final lightingOk =
        lightingConfirmed || held >= lightingWait;

    final progress = (held.inMilliseconds / dwell.inMilliseconds).clamp(0.0, 1.0);
    final ready = lightingOk && held >= dwell;
    return FlashReadyState(ready: ready, progress: progress);
  }

  void reset() => _heldSince = null;
}
