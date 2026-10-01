import '../services/api_service.dart' show KYCApiException;

// ─── A cancelled session ─────────────────────────────────────────────────────
//
// An organisation (or Myaza support) can cancel a verification session midway,
// reversibly. While it stays cancelled the server refuses to let the applicant
// reopen or continue it: `POST /session/start`, `PUT /session/:id/progress`
// and `POST /verify` answer 409 `{ error: 'session_cancelled', message }`, and
// `GET /status/:id` reports `status: 'cancelled'`.
//
// Retrying can never succeed until somebody uncancels it, so none of those
// refusals may read as a generic "try again". Every path routes to ONE
// dedicated screen that says what happened and offers only Close. These rules
// are pure so each path's decision is testable without a network. Mirrors the
// web and RN SDKs; keep the three in lockstep.

/// The server's error token, and the SDK's public error code for it.
const String kSessionCancelledCode = 'session_cancelled';

/// The `/status` value for a cancelled session (add-only vocabulary).
const String kCancelledStatus = 'cancelled';

/// The cancelled screen's title.
const String kSessionCancelledTitle = 'This verification was cancelled';

/// Shown when the server sent no message of its own.
const String kSessionCancelledMessage =
    'This verification was cancelled. Contact the organisation that sent it '
    'if you think this is a mistake.';

/// Whether [error] is the server refusing a cancelled session.
bool isSessionCancelledError(Object? error) =>
    error is KYCApiException && error.error == kSessionCancelledCode;

/// The words to show for a cancellation: the server's own message when it sent
/// one, otherwise the SDK's sentence.
String sessionCancelledText(String? serverMessage) {
  final trimmed = serverMessage?.trim();
  return (trimmed == null || trimmed.isEmpty) ? kSessionCancelledMessage : trimmed;
}

/// The message for a cancelled-session refusal, or null when [error] is
/// anything else.
String? sessionCancelledMessageFor(Object? error) => isSessionCancelledError(error)
    ? sessionCancelledText((error as KYCApiException).message)
    : null;

/// Whether a failed `/session/start` must STOP the flow.
///
/// Starting a session is best-effort: an outage, a timeout or any other
/// refusal leaves the flow running, because verifying is never conditional on
/// a session existing. A cancelled session is the one exception: the
/// applicant must not be walked into captures the server will refuse.
bool sessionStartStopsFlow(Object? error) => isSessionCancelledError(error);

/// Whether a `/status` value is the cancelled state (terminal: the wait ends).
bool isCancelledStatus(String? status) => status == kCancelledStatus;
