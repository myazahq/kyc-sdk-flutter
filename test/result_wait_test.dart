import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/biometric_copy.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/result_copy.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/result_wait.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

StatusResponse _read(String status, {String? reason, String? reasonCode}) => StatusResponse(
      verificationId: 'ver_1',
      status: status,
      reason: reason,
      reasonCode: reasonCode,
      createdAt: DateTime.utc(2026, 9, 7),
    );

// A fake clock: every sleep advances time by the requested amount.
class _Harness {
  int t = 0;
  final sleeps = <int>[];
  final List<StatusResponse?> queue;
  _Harness(this.queue);

  Future<VerificationOutcome> run() => awaitVerificationOutcome(
        fetchStatus: () async => queue.isEmpty ? null : queue.removeAt(0),
        sleep: (ms) async {
          sleeps.add(ms);
          t += ms;
        },
        nowMs: () => t,
        waitMs: 10000,
        pollMs: 1000,
      );
}

void main() {
  group('awaitVerificationOutcome', () {
    test('polls through the pending states and settles on the verdict', () async {
      final h = _Harness([
        _read('processing'),
        _read('processing'),
        _read('declined', reasonCode: 'biometric_auth_failed', reason: 'No match.'),
      ]);
      final out = await h.run() as SettledOutcome;
      expect(out.status, 'declined');
      expect(out.reason, 'No match.');
      expect(out.reasonCode, 'biometric_auth_failed');
      expect(h.sleeps, [1000, 1000]);
    });

    test('a failed read is skipped, never taken as a verdict', () async {
      final out = await _Harness([null, _read('approved')]).run() as SettledOutcome;
      expect(out.status, 'approved');
      expect(out.reason, isNull);
    });

    test('gives up at the deadline while still pending', () async {
      final h = _Harness(List.generate(20, (_) => _read('processing')));
      expect(await h.run(), isA<TimedOutOutcome>());
      expect(h.sleeps.length, 10);
    });

    test('review and error settle the wait like a verdict does', () async {
      expect(((await _Harness([_read('in_review')]).run()) as SettledOutcome).status, 'in_review');
      expect(((await _Harness([_read('error', reasonCode: 'system_error')]).run()) as SettledOutcome).reasonCode, 'system_error');
    });

    test('names the pending states', () {
      expect(['not_started', 'in_progress', 'processing'].map(isPendingStatus), everyElement(isTrue));
      expect(isPendingStatus('approved'), isFalse);
    });
  });

  group('describeWaiting', () {
    test('names the check on a re-authentication that waits, and the step elsewhere', () {
      expect(describeWaiting(scope: 'biometric-authentication', waitsForResult: true).title, "Checking it's you");
      expect(describeWaiting(scope: 'biometric-authentication', waitsForResult: false).title, 'Sending your face check');
      expect(describeWaiting(scope: 'biometric-enrollment', waitsForResult: false).title, 'Saving your selfie');
      expect(describeWaiting(scope: null, waitsForResult: false).title, 'Submitting your verification');
    });

    test('a retry in flight swaps the description and keeps the title', () {
      final c = describeWaiting(scope: 'biometric-authentication', waitsForResult: true, retry: (attempt: 2, total: 3));
      expect(c.title, "Checking it's you");
      expect(c.description, 'Connection issue, retrying (2/3).');
    });

    test("the org's own words replace the default field by field, and a retry keeps the custom title", () {
      final custom = describeWaiting(
        scope: 'biometric-authentication',
        waitsForResult: true,
        override: const BiometricCopyText(title: 'One moment, Ada'),
      );
      expect(custom.title, 'One moment, Ada');
      expect(custom.description, 'Matching your selfie against the photo on record. This usually takes a few seconds.');
      final retrying = describeWaiting(
        scope: 'biometric-authentication',
        waitsForResult: true,
        retry: (attempt: 2, total: 3),
        override: const BiometricCopyText(title: 'One moment, Ada', description: 'Hold still.'),
      );
      expect(retrying.title, 'One moment, Ada');
      expect(retrying.description, 'Connection issue, retrying (2/3).');
      expect(describeWaiting(scope: 'biometric-enrollment', waitsForResult: false, override: null).title, 'Saving your selfie');
    });

    test('carries no em dash', () {
      for (final scope in ['biometric-authentication', 'biometric-enrollment', null]) {
        for (final waits in [true, false]) {
          final c = describeWaiting(scope: scope, waitsForResult: waits, retry: (attempt: 1, total: 3));
          expect('${c.title} ${c.description}', isNot(contains('—')));
        }
      }
    });
  });

  group('describeOutcome', () {
    test('speaks to each outcome, preferring the server reason on a decline', () {
      final approved = describeOutcome(const SettledOutcome(status: 'approved'));
      expect(approved.tone, ResultTone.success);
      expect(approved.title, "You're verified");
      final declined = describeOutcome(const SettledOutcome(status: 'declined', reason: 'Your selfie did not match.', reasonCode: 'biometric_auth_failed'));
      expect(declined.tone, ResultTone.error);
      expect(declined.description, 'Your selfie did not match.');
      expect(describeOutcome(const SettledOutcome(status: 'in_review')).tone, ResultTone.info);
      final timedOut = describeOutcome(const TimedOutOutcome());
      expect(timedOut.tone, ResultTone.info);
      expect(timedOut.title, 'Still checking');
    });

    test("the org's own words replace the verdict screens, its declined description over the server reason", () {
      const verified = BiometricCopyText(title: 'Welcome back, Ada', description: 'You are signed in.');
      const declined = BiometricCopyText(description: 'Try again in better light.');
      final ok = describeOutcome(const SettledOutcome(status: 'approved'), verified: verified, declined: declined);
      expect(ok.tone, ResultTone.success);
      expect(ok.title, 'Welcome back, Ada');
      expect(ok.description, 'You are signed in.');
      final no = describeOutcome(
        const SettledOutcome(status: 'declined', reason: 'The selfie did not match.', reasonCode: 'x'),
        verified: verified,
        declined: declined,
      );
      expect(no.title, "We couldn't confirm it's you");
      expect(no.description, 'Try again in better light.');
      expect(describeOutcome(const TimedOutOutcome(), verified: verified, declined: declined).title, 'Still checking');
    });

    test('carries no em dash in anything the person reads', () {
      for (final o in const [
        SettledOutcome(status: 'approved'),
        SettledOutcome(status: 'declined'),
        SettledOutcome(status: 'error'),
        TimedOutOutcome(),
      ]) {
        final c = describeOutcome(o);
        expect('${c.title} ${c.description}', isNot(contains('—')));
      }
    });
  });
}
