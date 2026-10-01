import '../services/api_service.dart' show StatusResponse;
import 'session_cancelled.dart' show isCancelledStatus;

// ─── Waiting for a verdict in the flow ──────────────────────────────────────
//
// The platform is fire-and-forget: /verify answers in milliseconds and the
// worker settles the check afterwards. A re-authentication is the one flow
// whose verdict the person is waiting for RIGHT THERE, so the submitted step
// polls the publishable status endpoint (state + reason, never result data)
// until the check leaves its pending states. Pure and injectable, like the
// presence watch wait: the screen owns nothing but the rendering. Mirrors the
// web and RN SDKs' result-wait; keep the three in lockstep.

const int kResultWaitMs = 60 * 1000;
const int kResultPollMs = 1500;

/// The states a submitted check passes through before it settles.
const Set<String> _kPending = {'not_started', 'in_progress', 'processing'};

sealed class VerificationOutcome {
  const VerificationOutcome();
}

class SettledOutcome extends VerificationOutcome {
  final String status;
  final String? reason;
  final String? reasonCode;
  const SettledOutcome({required this.status, this.reason, this.reasonCode});
}

class TimedOutOutcome extends VerificationOutcome {
  const TimedOutOutcome();
}

/// The organisation cancelled the session while the person waited. Terminal,
/// and not a verdict: the screen hands over to the cancelled screen rather
/// than describing an outcome (config/session_cancelled.dart).
class CancelledOutcome extends VerificationOutcome {
  const CancelledOutcome();
}

bool isPendingStatus(String status) => _kPending.contains(status);

/// Poll until the check settles or the budget runs out. A failed read is not
/// a verdict: it is skipped and the next poll tries again, so a network blip
/// mid-wait never reads as an outcome.
Future<VerificationOutcome> awaitVerificationOutcome({
  /// One status read; null on any failure (the wait keeps going).
  required Future<StatusResponse?> Function() fetchStatus,
  Future<void> Function(int ms)? sleep,
  int Function()? nowMs,
  int waitMs = kResultWaitMs,
  int pollMs = kResultPollMs,
}) async {
  final doSleep = sleep ?? (ms) => Future<void>.delayed(Duration(milliseconds: ms));
  final now = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final deadline = now() + waitMs;
  for (;;) {
    final read = await fetchStatus();
    // Cancelled is terminal: waiting longer can never change it, and timing
    // out would tell the person to wait for a webhook that is not coming.
    if (read != null && isCancelledStatus(read.status)) return const CancelledOutcome();
    if (read != null && !isPendingStatus(read.status)) {
      return SettledOutcome(status: read.status, reason: read.reason, reasonCode: read.reasonCode);
    }
    if (now() >= deadline) return const TimedOutOutcome();
    await doSleep(pollMs);
  }
}
