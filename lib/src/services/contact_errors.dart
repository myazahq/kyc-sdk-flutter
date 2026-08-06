import 'api_service.dart';

// ─── Contact-verification error copy ──────────────────────────────────────────
//
// Maps the server's `error` codes (KYCApiException.error) for the OTP send /
// check endpoints to user-facing copy. Mirrors the web SDK's contact-errors.

String describeSendError(Object err) {
  final code = err is KYCApiException ? err.error : null;
  return switch (code) {
    'invalid_destination' =>
      'That does not look valid. Please check and try again.',
    'send_rate_limited' =>
      'Too many codes requested. Please wait a while and try again.',
    'send_failed' => 'We could not send the code. Please try again.',
    'network_error' || 'timeout' =>
      'Network error. Check your connection and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}

String describeCheckError(Object err) {
  final code = err is KYCApiException ? err.error : null;
  return switch (code) {
    'invalid_code' => 'That code is not correct. Please try again.',
    'challenge_expired' => 'This code has expired. Request a new one.',
    'too_many_attempts' =>
      'Too many incorrect attempts. Request a new code.',
    'challenge_not_found' =>
      'This code is no longer valid. Request a new one.',
    'network_error' || 'timeout' =>
      'Network error. Check your connection and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}
