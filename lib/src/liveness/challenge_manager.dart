import 'dart:math';

import 'liveness_types.dart';

// ─── Challenge manager ────────────────────────────────────────────────────────
//
// Randomly selects `count` challenges from the pool at construction/reset and
// tracks which have been completed. Timing is intentionally NOT owned here —
// the liveness provider holds the dart:async Timer and calls
// currentTimeoutSeconds to know how long each challenge gets.
//
// Selection mirrors the web SDK's liveness/challenge-manager.ts: a head TURN is
// always one of the prompts (in a random position), gestures that can trigger
// each other never appear together, and no prompt appears twice.

/// Gestures within a group never appear together, because one can
/// accidentally trigger the other (head movement overlaps).
const List<Set<LivenessChallenge>> _similarityGroups = [
  {LivenessChallenge.nod, LivenessChallenge.turn},
];

bool _areSimilar(LivenessChallenge a, LivenessChallenge b) =>
    _similarityGroups.any((g) => g.contains(a) && g.contains(b));

class ChallengeManager {
  final List<ChallengeConfig> pool;
  final int count;

  late final List<ChallengeConfig> _selected;
  int _currentIndex = 0;

  // ── Factory constructor clamps count to valid range ────────────────────────

  factory ChallengeManager({
    List<ChallengeConfig>? pool,
    int count = 2,
  }) {
    final effectivePool = pool ?? kDefaultChallengePool;
    final clampedCount = count.clamp(1, effectivePool.length);
    return ChallengeManager._(pool: effectivePool, count: clampedCount);
  }

  /// No gesture challenges — flash-only liveness (`livenessMode: 'flash'`),
  /// where the screen-reflection sequence IS the check.
  ///
  /// Deliberately a separate constructor rather than `count: 0`: the factory
  /// clamps count to at least 1 so a stray `challengeCount: 0` in a consumer's
  /// config can never silently disable gesture liveness. Skipping gestures has
  /// to be asked for explicitly.
  factory ChallengeManager.none() =>
      ChallengeManager._(pool: const [], count: 0);

  /// Passive Liveness (`livenessMode: 'passive'`): the single hold prompt. No
  /// gestures and no flash; the server's liveness model does the judging.
  factory ChallengeManager.passive() =>
      ChallengeManager._(pool: const [kHoldChallenge], count: 1);

  /// The prompts the workflow's liveness method asks for. The flash is not a
  /// prompt here: the screen runs it at the capture seam.
  factory ChallengeManager.forMode(
    String livenessMode, {
    List<ChallengeConfig>? pool,
    int count = 2,
  }) =>
      switch (livenessMode) {
        'flash' => ChallengeManager.none(),
        'passive' => ChallengeManager.passive(),
        _ => ChallengeManager(pool: pool, count: count),
      };

  ChallengeManager._({required this.pool, required this.count}) {
    _selected = _pickRandom();
  }

  // ── Accessors ───────────────────────────────────────────────────────────────

  /// The currently active challenge, or null when all challenges are done.
  ChallengeConfig? get current =>
      _currentIndex < _selected.length ? _selected[_currentIndex] : null;

  /// How many seconds the current challenge allows before timing out.
  /// Returns 0 when [isComplete].
  int get currentTimeoutSeconds => current?.timeoutSeconds ?? 0;

  /// The index (0-based) of the challenge being attempted.
  int get currentIndex => _currentIndex;

  /// How many challenges have been completed.
  int get completedCount => _currentIndex;

  /// How many challenges were selected for this session.
  int get totalCount => _selected.length;

  /// True once all selected challenges have been completed.
  bool get isComplete => _currentIndex >= _selected.length;

  /// Read-only snapshot of the challenges selected for this session.
  List<ChallengeConfig> get selectedChallenges =>
      List.unmodifiable(_selected);

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// Advance to the next challenge. No-op when already complete.
  void advance() {
    if (!isComplete) _currentIndex++;
  }

  /// Re-shuffle the pool and restart from challenge 0.
  void reset() {
    _currentIndex = 0;
    _selected
      ..clear()
      ..addAll(_pickRandom());
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  List<ChallengeConfig> _pickRandom() {
    if (count <= 0) return <ChallengeConfig>[];
    final random = Random();
    final shuffled = List<ChallengeConfig>.from(pool)..shuffle(random);
    final picked = <ChallengeConfig>[];
    bool taken(ChallengeConfig c) => picked.any((p) => p.type == c.type);

    // A head TURN is always one of the prompts, because the server's
    // shape-from-movement test needs one: a turn swings the nose across the
    // face, which a flat picture cannot do. The rest stay random.
    for (final c in shuffled) {
      if (c.type == LivenessChallenge.turn) {
        picked.add(c);
        break;
      }
    }

    // Greedily add challenges that aren't similar to those already picked.
    for (final c in shuffled) {
      if (picked.length >= count) break;
      if (taken(c) || picked.any((p) => _areSimilar(p.type, c.type))) continue;
      picked.add(c);
    }

    // The similarity rule was too strict for this pool: fill the rest.
    for (final c in shuffled) {
      if (picked.length >= count) break;
      if (!taken(c)) picked.add(c);
    }

    // The turn went first to guarantee it; shuffle so its position is random.
    return picked..shuffle(random);
  }
}

/// The prompts a run used, in order, as wire names for the liveness claim
/// (`integrity.liveness.challenges`): 'nod', 'turn', 'blink', 'smile',
/// 'flash', 'hold'.
///
/// [gestures] are the prompts the manager ran. The flash runs at the capture
/// seam, so it is placed here: after the gestures in 'both', alone in 'flash',
/// and FIRST when a flash-only check fell back to gestures.
List<String> livenessClaimChallenges({
  required String mode,
  required List<LivenessChallenge> gestures,
  bool fellBackToGestures = false,
}) {
  final names = [for (final g in gestures) g.name];
  if (fellBackToGestures) return ['flash', ...names];
  return switch (mode) {
    'flash' => const ['flash'],
    'both' => [...names, 'flash'],
    _ => names,
  };
}
