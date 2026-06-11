import '../config/kyc_config.dart';
import 'api_service.dart';

// ─── mapToKycError — raw API error → typed KYCError ────────────────────────────
//
// Used at every call site that talks to the server (upload, verify) so the
// `onError` callback always receives a documented, typed `code`. Mirrors the
// web SDK's `mapToKycError` (lib/errors.ts) so the two platforms surface the
// same codes.

/// Which operation failed — picks the fallback code for non-HTTP failures.
enum ErrorContext { upload, verify }

KYCError mapToKycError(Object error, {required ErrorContext context}) {
  final uploadCtx = context == ErrorContext.upload;

  if (error is KYCApiException) {
    switch (error.error) {
      case 'insufficient_credits':
        return KYCError(
          code: 'insufficient_credits',
          message:
              'Organization credits exhausted. Contact your administrator.',
          details: error.details,
        );
      case 'invalid_api_key':
        return KYCError(
          code: 'invalid_api_key',
          message: error.message ?? 'Invalid or revoked API key.',
        );
      case 'id_type_not_allowed':
        return const KYCError(
          code: 'feature_disabled',
          message:
              "This ID type isn't enabled for your organization. Contact your administrator to request access.",
        );
      case 'feature_disabled':
        return KYCError(
          code: 'feature_disabled',
          message: switch (error.details?['feature']) {
            'document_verification' =>
              'Document verification is currently disabled for your organization.',
            'gov_db_check' =>
              'Government database verification is currently disabled for your organization.',
            _ => error.message ??
                'This verification feature is currently disabled for your organization.',
          },
          details: error.details,
        );
      case 'upload_failed':
        return KYCError(
          code: 'upload_failed',
          message: error.message ?? 'A file failed to upload. Please try again.',
        );
      case 'timeout':
      case 'network_error':
      case 'connection_error':
        return const KYCError(
          code: 'network_error',
          message: 'Connection failed. Please try again.',
        );
    }

    // 5xx that survived retries.
    if (error.statusCode >= 500 || error.statusCode == 0) {
      return KYCError(
        code: uploadCtx ? 'upload_failed' : 'network_error',
        message: 'A server error occurred. Please try again in a moment.',
      );
    }

    return KYCError(
      code: uploadCtx ? 'upload_failed' : 'unknown',
      message: error.message ?? 'Something went wrong. Please try again.',
    );
  }

  return KYCError(
    code: uploadCtx ? 'upload_failed' : 'unknown',
    message: 'Something went wrong. Please try again.',
  );
}
