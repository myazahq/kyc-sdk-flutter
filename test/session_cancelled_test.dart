import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/result_copy.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/result_wait.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/session_cancelled.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/submit_recovery.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/kyc_error_mapper.dart';

// An organisation can cancel a verification session midway. The server then
// answers 409 { error: 'session_cancelled', message } from /session/start,
// /session/:id/progress and /verify, and status 'cancelled' from /status/:id.
// Retrying can never succeed, so no path may offer Try again for it.

const _serverMessage =
    'This verification was cancelled. Contact the organisation that sent it if you think this is a mistake.';

KYCApiException _cancelled([String? message = _serverMessage]) =>
    KYCApiException(statusCode: 409, error: kSessionCancelledCode, message: message);

StatusResponse _read(String status, {String? reason}) => StatusResponse(
      verificationId: 'ver_1',
      status: status,
      reason: reason,
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  group('reading the refusal', () {
    test('takes the server message off a session_cancelled refusal', () {
      expect(sessionCancelledMessageFor(_cancelled()), _serverMessage);
    });

    test('falls back to the SDK sentence when the server sent none', () {
      expect(sessionCancelledMessageFor(_cancelled(null)), kSessionCancelledMessage);
      expect(sessionCancelledMessageFor(_cancelled('   ')), kSessionCancelledMessage);
    });

    test('ignores every other failure, including other 409s', () {
      const used = KYCApiException(statusCode: 409, error: 'handoff_session_used');
      expect(sessionCancelledMessageFor(used), isNull);
      expect(sessionCancelledMessageFor(Exception('offline')), isNull);
      expect(sessionCancelledMessageFor(null), isNull);
    });
  });

  group('/session/start', () {
    test('stops the flow on a cancellation', () {
      expect(sessionStartStopsFlow(_cancelled()), isTrue);
    });

    test('keeps every other start failure best-effort', () {
      expect(sessionStartStopsFlow(const KYCApiException(statusCode: 500, error: 'internal_error')), isFalse);
      expect(sessionStartStopsFlow(const KYCApiException(statusCode: 409, error: 'session_unavailable')), isFalse);
      expect(sessionStartStopsFlow(Exception('offline')), isFalse);
    });
  });

  group('the submission', () {
    test('maps to its own error code, never a retry', () {
      for (final context in ErrorContext.values) {
        final e = mapToKycError(_cancelled(), context: context);
        expect(e.code, kSessionCancelledCode);
        expect(e.message, _serverMessage);
      }
      final bare = mapToKycError(_cancelled(null), context: ErrorContext.verify);
      expect(bare.message, isNot(contains('try again')));
    });

    test('offers no Go back', () {
      const order = [KYCStep.consent, KYCStep.idType, KYCStep.idInput, KYCStep.liveness, KYCStep.submitted];
      expect(recoveryStepFor(kSessionCancelledCode, order), isNull);
    });
  });

  group('the status poll', () {
    test('ends the wait on cancelled instead of timing out', () async {
      final queue = <StatusResponse?>[_read('processing'), _read('cancelled', reason: 'Selfie mismatch.')];
      var t = 0;
      final sleeps = <int>[];
      final out = await awaitVerificationOutcome(
        fetchStatus: () async => queue.isEmpty ? null : queue.removeAt(0),
        sleep: (ms) async {
          sleeps.add(ms);
          t += ms;
        },
        nowMs: () => t,
        waitMs: 10000,
        pollMs: 1000,
      );
      expect(out, isA<CancelledOutcome>());
      expect(sleeps, [1000]);
    });

    test('words a cancelled outcome as cancelled, never with the checks reason', () {
      final copy = describeOutcome(const CancelledOutcome());
      expect(copy.title, kSessionCancelledTitle);
      expect(copy.description, kSessionCancelledMessage);
      expect(copy.description, isNot(contains('—')));
    });
  });
}
