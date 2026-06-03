import 'dart:math';

import 'liveness_types.dart';

// ─── Challenge manager ────────────────────────────────────────────────────────
//
// Randomly selects `count` challenges from the pool at construction/reset and
// tracks which have been completed. Timing is intentionally NOT owned here —
// the liveness provider holds the dart:async Timer and calls
// currentTimeoutSeconds to know how long each challenge gets.

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
    final shuffled = List<ChallengeConfig>.from(pool)..shuffle(Random());
    return shuffled.take(count).toList();
  }
}
