import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_watch_wait.dart';

// A submit-time report waits for its watch. The watch is minted seconds after
// the submission is accepted and the ingest drops anything posted before it,
// indistinguishably from an unknown user (iPhone + S24, 2026-09-07). A fresh
// pin waits; an old pin with no live watch is told so. A port of the RN SDK's
// presenceWatchWait.test.ts — keep the two in lockstep.

class _Harness {
  _Harness(List<String?> statuses)
      : _reads = List.of(statuses),
        _last = statuses.isEmpty ? null : statuses.last;
  final List<String?> _reads;
  final String? _last;
  DateTime _t = DateTime.utc(2026, 9, 7, 8);
  final List<Duration> sleeps = [];

  Future<String?> read() async => _reads.isNotEmpty ? _reads.removeAt(0) : _last;
  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    _t = _t.add(d);
  }

  DateTime now() => _t;

  Future<WatchPresence> run({required bool fresh}) =>
      awaitWatch(fresh: fresh, fetchStatus: read, sleep: sleep, now: now);
}

void main() {
  group('awaitWatch', () {
    test('a fresh pin waits through the previous cycle and the gap until live', () async {
      final h = _Harness(['inconclusive', 'not_started', 'in_progress']);
      expect(await h.run(fresh: true), WatchPresence.live);
      expect(h.sleeps, [kWatchPoll, kWatchPoll]);
    });

    test('a fresh pin gives up at the deadline when no watch ever appears', () async {
      final h = _Harness(['not_started']);
      expect(await h.run(fresh: true), WatchPresence.absent);
      expect(h.sleeps.length, kWatchWait.inSeconds ~/ kWatchPoll.inSeconds);
    });

    test('a fresh pin keeps waiting through a failed read; unknown only when every read failed', () async {
      expect(await _Harness([null, 'in_progress']).run(fresh: true), WatchPresence.live);
      expect(await _Harness([null]).run(fresh: true), WatchPresence.unknown);
    });

    test('an old pin reads once: live, absent, or unknown', () async {
      expect(await _Harness(['in_progress']).run(fresh: false), WatchPresence.live);
      final absent = _Harness(['verified']);
      expect(await absent.run(fresh: false), WatchPresence.absent);
      expect(absent.sleeps, isEmpty);
      expect(await _Harness([null]).run(fresh: false), WatchPresence.unknown);
    });
  });

  group('pinIsFresh', () {
    final now = DateTime.utc(2026, 9, 7, 8);
    String savedAgo(Duration d) => now.subtract(d).toIso8601String();

    test('is fresh inside the window and not past it', () {
      expect(pinIsFresh(savedAgo(Duration.zero), now: now), isTrue);
      expect(pinIsFresh(savedAgo(kFreshPinWindow), now: now), isTrue);
      expect(pinIsFresh(savedAgo(kFreshPinWindow + const Duration(seconds: 1)), now: now), isFalse);
    });

    test('an unparseable stamp is never fresh', () {
      expect(pinIsFresh('yesterday', now: now), isFalse);
    });
  });
}
