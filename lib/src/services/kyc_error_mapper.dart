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

/// Server error tokens with a dedicated user-facing message, keyed by the
/// response body's `error`. Mostly the business (KYB) submission path. Checked
/// **before** the generic status branches so e.g. a 500 `pricing_not_configured`
/// doesn't read as a transient server blip, and a 422 doesn't fall through to a
/// bare `unknown`. Mirrors the web SDK's `CODED_ERRORS` (lib/errors.ts).
const Map<String, ({String code, String message})> _codedErrors = {
  'workflow_not_found': (
    code: 'invalid_workflow',
    message:
        'This verification workflow is unavailable. It may have been unpublished — please try again later.',
  ),
  'workflow_subject_mismatch': (
    code: 'invalid_workflow',
    message:
        'This workflow cannot accept a business submission. Contact the organization that sent you here.',
  ),
  'business_verifications_disabled': (
    code: 'feature_disabled',
    message:
        'Business verification is not enabled for this organization. Contact your administrator to request access.',
  ),
  'country_mismatch': (
    code: 'invalid_workflow',
    message:
        "The submitted country doesn't match this workflow's configuration. Please try again.",
  ),
  'product_unsupported': (
    code: 'invalid_workflow',
    message:
        'The selected verification product is not offered by this workflow. Please try again.',
  ),
  'registration_name_required': (
    code: 'unknown',
    message: 'Please enter the registered business name to continue.',
  ),
  'only_test_ids_allowed': (
    code: 'unknown',
    message:
        'Sandbox mode accepts only published test registration numbers (e.g. RC0000001 or RC0000002).',
  ),
  'pricing_not_configured': (
    code: 'unknown',
    message:
        'Verification pricing has not been configured for this organization. Please contact support.',
  ),
  // The business-application sections DO have screens now, so these are
  // recoverable: the applicant goes back and fills in what's missing. Reaching
  // them means the client-side gate let something through (e.g. the workflow
  // was republished mid-flow with a newly required slot).
  'missing_documents': (
    code: 'unknown',
    message:
        'Some required business documents are missing. Please go back and upload them.',
  ),
  'missing_company_info': (
    code: 'unknown',
    message:
        'Some required company details are missing. Please go back and complete them.',
  ),
  'key_people_required': (
    code: 'unknown',
    message:
        'Please go back and list the required directors/owners to continue.',
  ),
};

KYCError mapToKycError(Object error, {required ErrorContext context}) {
  final uploadCtx = context == ErrorContext.upload;

  if (error is KYCApiException) {
    final coded = _codedErrors[error.error];
    if (coded != null) {
      return KYCError(code: coded.code, message: coded.message);
    }

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
      // The SDK caught its OWN inconsistency before making a request. It is
      // neither a network fault nor a server fault, and titling it "Connection
      // Failed" sends everyone — the applicant, and whoever they report it to —
      // looking at the network for something that never left the device.
      case 'invalid_state':
        return KYCError(
          code: 'invalid_state',
          message: error.message ?? 'Something is missing. Please try again.',
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

    // Nothing came back at all — DNS, routing, a refused connection, a device
    // with no path to the host. Kept SEPARATE from a 5xx on purpose: telling
    // somebody the server errored when their request never arrived sends them
    // (and whoever they report it to) looking through server logs for a request
    // that was never made.
    if (error.statusCode == 0) {
      return KYCError(
        code: uploadCtx ? 'upload_failed' : 'network_error',
        message: error.message ?? "Couldn't reach the server. Check your connection and try again.",
      );
    }

    // 5xx that survived retries — the request DID arrive.
    if (error.statusCode >= 500) {
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
