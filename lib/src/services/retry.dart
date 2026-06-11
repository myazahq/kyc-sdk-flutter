import 'dart:async';
import 'dart:math';

import 'api_service.dart';

// ─── withRetry — shared retry/backoff for the SDK's network operations ─────────
//
// Wraps the SDK's network calls (media upload, verify submission) so transient
// failures — lost connection, request timeouts, 5xx — are retried with
// exponential backoff + jitter before giving up. Terminal failures (4xx auth /
// credits / forbidden) are NOT retried; they surface immediately.
//
// Mirrors the web SDK's `withRetry` (lib/retry.ts) so both platforms behave
// identically. After retries are exhausted the original exception is rethrown —
// the caller maps it to a typed KYCError for `onError`.

/// Whether a [KYCApiException] (or other error) is transient and worth retrying.
/// 5xx + the connectivity error codes are transient; 4xx are terminal.
bool isTransientError(Object error) {
  if (error is KYCApiException) {
    if (error.statusCode >= 500 || error.statusCode == 0) return true;
    return error.error == 'network_error' ||
        error.error == 'timeout' ||
        error.error == 'connection_error';
  }
  // A bare TimeoutException (e.g. from a manual .timeout()) is transient.
  if (error is TimeoutException) return true;
  return false;
}

/// Runs [action], retrying on transient errors with exponential backoff +
/// jitter. [onRetry] is invoked before each retry with the upcoming attempt
/// number (2-based) and the total, so the UI can show "Retrying (2/3)…".
/// Rethrows the last error once attempts are exhausted (or immediately for a
/// terminal error).
Future<T> withRetry<T>(
  Future<T> Function() action, {
  int retries = 3,
  Duration baseDelay = const Duration(milliseconds: 500),
  double factor = 2.0,
  Duration maxDelay = const Duration(seconds: 4),
  void Function(int attempt, int total)? onRetry,
}) async {
  final rng = Random();
  Object? lastError;

  for (var attempt = 1; attempt <= retries; attempt++) {
    try {
      return await action();
    } catch (e) {
      lastError = e;
      final hasMore = attempt < retries;
      if (!hasMore || !isTransientError(e)) rethrow;

      onRetry?.call(attempt + 1, retries);

      final backoffMs =
          min(baseDelay.inMilliseconds * pow(factor, attempt - 1), maxDelay.inMilliseconds.toDouble());
      // Full jitter — spread retries so a flaky network doesn't see synchronized bursts.
      final delayMs = (rng.nextDouble() * backoffMs).round();
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
  // Unreachable in practice (the loop either returns or rethrows), but satisfies
  // the analyzer's control-flow check.
  throw lastError ?? StateError('withRetry exhausted with no error');
}
