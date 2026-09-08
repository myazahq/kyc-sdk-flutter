import '../services/api_service.dart' show KYCApiException;
import 'kyc_config.dart' show KYCError;

// ─── Biometric re-authentication — the pure half ─────────────────────────────
//
// Mirrors the web and RN SDKs' error mapping (keep the three in lockstep): a
// technical failure in the SDK's typed vocabulary plus a message a person can
// read, never the server's own wording.

KYCError mapBiometricAuthError(Object err) {
  if (err is KYCApiException) {
    if (err.statusCode == 404 && err.error == 'not_enrolled') {
      return const KYCError(
        code: 'unknown',
        message: "You're not set up for face verification yet.",
      );
    }
    if (err.statusCode == 402) {
      return const KYCError(
        code: 'insufficient_credits',
        message: 'Face verification is temporarily unavailable.',
      );
    }
    if (err.statusCode == 401 || err.statusCode == 403) {
      return const KYCError(
        code: 'invalid_api_key',
        message: 'This app is not authorised for face verification.',
      );
    }
  }
  return const KYCError(
    code: 'network_error',
    message: 'Something went wrong. Please try again.',
  );
}

String defaultReauthLabel(String? companyName) =>
    companyName == null || companyName.trim().isEmpty
        ? "Verify it's you"
        : "Verify it's you with $companyName";
