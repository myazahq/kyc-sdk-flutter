import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_watch_status.dart';

// The body is the server's PresenceStatusView (kyc-core,
// src/lib/address-intel/presence/status.ts).

void main() {
  test('a running check reads its progress and dates', () {
    final s = parsePresenceWatchStatus({
      'status': 'in_progress',
      'watchId': 'aw_1',
      'startedAt': '2026-10-01T08:00:00.000Z',
      'deadlineAt': '2026-10-08T08:00:00.000Z',
      'decidedAt': null,
      'progress': {'score': 0.4, 'nightsObserved': 2, 'daysObserved': 2},
      'tier': 'foreground',
      'alwaysOn': true,
      'nextCycleAt': null,
      'stopped': false,
    })!;
    expect(s.state, PresenceWatchState.inProgress);
    expect(s.progress, 0.4);
    expect(s.nightsObserved, 2);
    expect(s.daysObserved, 2);
    expect(s.tier, 'foreground');
    expect(s.alwaysOn, isTrue);
    expect(s.deadlineAt, DateTime.utc(2026, 10, 8, 8));
    expect(s.decidedAt, isNull);
    expect(s.stopped, isFalse);
  });

  test('no check answers notStarted with nothing else', () {
    final s = parsePresenceWatchStatus({'status': 'not_started', 'progress': null})!;
    expect(s.state, PresenceWatchState.notStarted);
    expect(s.progress, isNull);
    expect(s.nightsObserved, isNull);
  });

  test('a revoked check is stopped even without the flag', () {
    expect(parsePresenceWatchStatus({'status': 'revoked'})!.stopped, isTrue);
    expect(parsePresenceWatchStatus({'status': 'verified', 'stopped': true})!.stopped, isTrue);
  });

  test('a status word this build does not know is unknown, and kept', () {
    final s = parsePresenceWatchStatus({'status': 'paused'})!;
    expect(s.state, PresenceWatchState.unknown);
    expect(s.rawStatus, 'paused');
  });

  test('a body with no status is null; a score outside 0..1 is clamped', () {
    expect(parsePresenceWatchStatus(null), isNull);
    expect(parsePresenceWatchStatus({'progress': {}}), isNull);
    final s = parsePresenceWatchStatus({
      'status': 'verified',
      'progress': {'score': 1.4},
    })!;
    expect(s.progress, 1.0);
  });
}
