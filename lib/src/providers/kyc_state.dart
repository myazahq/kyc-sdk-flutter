import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../services/api_service.dart';
import '../services/nfc_reader.dart';
import '../services/mrz_parser.dart';

// ─── KYC flow step ────────────────────────────────────────────────────────────
//
// The step set the flow can render. The actual ORDER (and which optional steps
// are present) is computed per config + state by `buildStepOrder` in
// step_order.dart — the single source of truth for navigation and the progress
// bar. A base individual flow is:
//   • Document IDs:    consent → idType → documentCapture → liveness → submitted
//   • Number-only IDs: consent → idType → idInput         → liveness → submitted
// with optional steps inserted when configured: contact verification (email /
// phone OTP) after consent, country-select before id-type, and proof-of-address
// / questionnaire after liveness.

enum KYCStep {
  consent,
  contactEmail,
  contactPhone,
  countrySelect,
  idType,
  documentCapture,
  idInput,
  nfc,
  liveness,
  proofOfAddress,
  questionnaire,
  businessDetails,
  submitted,
}

// ─── Media IDs (returned by /api/kyc/upload during capture) ──────────────────

class KYCMediaIds {
  final String? documentFront;
  final String? documentBack;
  final String? selfie;
  final String? documentFrontVideo;
  final String? documentBackVideo;
  final String? livenessVideo;
  final String? proofOfAddress;

  const KYCMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
    this.proofOfAddress,
  });

  KYCMediaIds copyWith({
    String? documentFront,
    String? documentBack,
    String? selfie,
    String? documentFrontVideo,
    String? documentBackVideo,
    String? livenessVideo,
    String? proofOfAddress,
  }) =>
      KYCMediaIds(
        documentFront: documentFront ?? this.documentFront,
        documentBack: documentBack ?? this.documentBack,
        selfie: selfie ?? this.selfie,
        documentFrontVideo: documentFrontVideo ?? this.documentFrontVideo,
        documentBackVideo: documentBackVideo ?? this.documentBackVideo,
        livenessVideo: livenessVideo ?? this.livenessVideo,
        proofOfAddress: proofOfAddress ?? this.proofOfAddress,
      );

  bool get hasAny =>
      documentFront != null ||
      documentBack != null ||
      selfie != null ||
      documentFrontVideo != null ||
      documentBackVideo != null ||
      livenessVideo != null ||
      proofOfAddress != null;
}

// ─── Server-driven SDK config (fetched from /api/kyc/config) ─────────────────

enum ServerConfigStatus { loading, ready, error }

class ServerSdkConfig {
  final ServerConfigStatus status;
  final List<SdkConfigIdType> idTypes;
  final String? environment;
  final String? error;

  /// HTTP status of the failed config request, if [status] is `error`.
  final int? statusCode;

  /// True when the failure is a hard, non-recoverable auth error (invalid API
  /// key / forbidden) — the flow can't proceed, so the modal shows a blocking
  /// error screen instead of silently falling back to the prop ID-type list.
  final bool fatal;

  /// Org branding (logo, name, color) returned by /api/kyc/config. Consumed
  /// when the consumer sets `appearance.logo = 'default'`.
  final SdkConfigBranding? branding;

  const ServerSdkConfig({
    required this.status,
    this.idTypes = const [],
    this.environment,
    this.error,
    this.statusCode,
    this.fatal = false,
    this.branding,
  });

  static const ServerSdkConfig loading =
      ServerSdkConfig(status: ServerConfigStatus.loading);

  /// Returns the per-ID feature flags for the given (country, idType), or
  /// null if the ID isn't in the access list (or config hasn't loaded yet).
  SdkIdTypeFeatures? featuresFor(String country, String idType) {
    return rowFor(country, idType)?.features;
  }

  /// Returns the raw server config row for the given (country, idType), or null
  /// if not granted (or config hasn't loaded). Callers pass its metadata into
  /// [resolveIdTypeDefinition] to synthesize definitions for Global-Document IDs.
  SdkConfigIdType? rowFor(String country, String idType) {
    for (final row in idTypes) {
      if (row.country == country && row.idType == idType) return row;
    }
    return null;
  }
}

// ─── Submission result (returned by /api/kyc/verify — async) ─────────────────

class KYCSubmissionResult {
  final String verificationId;
  /// Always 'pending' immediately after submission. Final result arrives via
  /// webhook to the org's backend.
  final String status;

  const KYCSubmissionResult({
    required this.verificationId,
    required this.status,
  });
}

// ─── KYC state ────────────────────────────────────────────────────────────────

class KYCState {
  final KYCStep currentStep;

  /// The country picked in the country-select step (multi-region flows). Null
  /// for single-country flows — the effective country then falls back to
  /// `config.country`. See `effectiveCountry` in step_order.dart.
  final String? selectedCountry;

  /// The resolved definition for the picked ID type (curated or synthesized from
  /// the server config). Null until the user selects one.
  final IdTypeConfig? selectedIdType;
  final String? idNumber;
  final UserData? userData;
  final KYCMediaIds mediaIds;
  final KYCSubmissionResult? submissionResult;
  final String? error;
  final bool isLoading;
  final String documentScanPhase; // 'front' | 'back' | 'complete'

  /// Review phase communicated by DocumentCaptureScreen so the parent
  /// (_KycFlowWidget) can update the step header title dynamically.
  /// Values: 'camera' | 'front_preview' | 'camera_back' | 'review'
  final String docReviewPhase;

  /// True while a step is showing a full-bleed camera and wants the sheet's
  /// chrome (header, padding, scroll) out of the way. Raised by the step
  /// itself, because only it knows whether the camera is actually on screen —
  /// the primer, permission, preview and review sub-screens all keep chrome.
  final bool immersiveCapture;

  /// Server-driven config: which IDs the org may verify and which SDK
  /// features apply per ID. Fetched once from /api/kyc/config on mount.
  final ServerSdkConfig serverConfig;

  /// Answers collected by the questionnaire step (empty until answered). Money
  /// fields store both `<key>` (amount) and `<key>_currency`. Submitted under
  /// `questionnaire` on /verify.
  final Map<String, dynamic> questionnaireAnswers;

  /// Capture-integrity claim from the liveness step (mode + flash outcome).
  /// Submitted under `metadata.device.integrity`, which the server stores as
  /// `deviceMetadata.integrity` and independently re-scores against the
  /// recorded video. Empty = the step didn't report one.
  final Map<String, dynamic> integrity;

  /// The proof-of-address document type key picked in the PoA step (e.g.
  /// `utility_bill`). Submitted as `proofOfAddressType`.
  final String? poaDocumentType;

  /// Contact-verification proofs (email/phone OTP). Tokens are submitted under
  /// `contact` on /verify; the addresses are kept so a returning user sees the
  /// verified state.
  final String? emailToken;
  final String? emailAddress;
  final String? phoneToken;
  final String? phoneNumber;

  /// eMRTD chip data read in the NFC step (null until read or if skipped).
  /// Submitted under `nfc` on /verify.
  final NfcChipData? nfcChipData;

  /// MRZ read off the captured document photo. Carries the BAC key, so the
  /// chip step can skip straight to reading instead of asking for a second
  /// camera pass.
  final MrzScan? mrzScan;

  /// Business (KYB) details collected in the business-details step: the picked
  /// registry country, product key, registration number, and optional
  /// registered name. Submitted under `business` on /verify.
  final String? businessCountry;
  final String? businessProduct;
  final String? registrationNumber;
  final String? registrationName;

  const KYCState({
    this.currentStep = KYCStep.consent,
    this.selectedCountry,
    this.selectedIdType,
    this.idNumber,
    this.userData,
    this.mediaIds = const KYCMediaIds(),
    this.submissionResult,
    this.error,
    this.isLoading = false,
    this.documentScanPhase = 'front',
    this.docReviewPhase = 'camera',
    this.immersiveCapture = false,
    this.serverConfig = ServerSdkConfig.loading,
    this.questionnaireAnswers = const {},
    this.integrity = const {},
    this.poaDocumentType,
    this.emailToken,
    this.emailAddress,
    this.phoneToken,
    this.phoneNumber,
    this.nfcChipData,
    this.mrzScan,
    this.businessCountry,
    this.businessProduct,
    this.registrationNumber,
    this.registrationName,
  });

  KYCState copyWith({
    KYCStep? currentStep,
    String? selectedCountry,
    IdTypeConfig? selectedIdType,
    String? idNumber,
    UserData? userData,
    KYCMediaIds? mediaIds,
    KYCSubmissionResult? submissionResult,
    String? error,
    bool? isLoading,
    String? documentScanPhase,
    String? docReviewPhase,
    bool? immersiveCapture,
    ServerSdkConfig? serverConfig,
    Map<String, dynamic>? questionnaireAnswers,
    Map<String, dynamic>? integrity,
    String? poaDocumentType,
    String? emailToken,
    String? emailAddress,
    String? phoneToken,
    String? phoneNumber,
    NfcChipData? nfcChipData,
    MrzScan? mrzScan,
    String? businessCountry,
    String? businessProduct,
    String? registrationNumber,
    String? registrationName,
    // Picking a new country invalidates the selected ID; copyWith can't null a
    // field via `?? this`, so this explicit flag clears it (and its number).
    bool clearSelectedIdType = false,
  }) =>
      KYCState(
        currentStep: currentStep ?? this.currentStep,
        selectedCountry: selectedCountry ?? this.selectedCountry,
        selectedIdType:
            clearSelectedIdType ? null : (selectedIdType ?? this.selectedIdType),
        idNumber: clearSelectedIdType ? null : (idNumber ?? this.idNumber),
        userData: userData ?? this.userData,
        mediaIds: mediaIds ?? this.mediaIds,
        submissionResult: submissionResult ?? this.submissionResult,
        error: error ?? this.error,
        isLoading: isLoading ?? this.isLoading,
        documentScanPhase: documentScanPhase ?? this.documentScanPhase,
        docReviewPhase: docReviewPhase ?? this.docReviewPhase,
        immersiveCapture: immersiveCapture ?? this.immersiveCapture,
        serverConfig: serverConfig ?? this.serverConfig,
        questionnaireAnswers:
            questionnaireAnswers ?? this.questionnaireAnswers,
        integrity: integrity ?? this.integrity,
        poaDocumentType: poaDocumentType ?? this.poaDocumentType,
        emailToken: emailToken ?? this.emailToken,
        emailAddress: emailAddress ?? this.emailAddress,
        phoneToken: phoneToken ?? this.phoneToken,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        nfcChipData: nfcChipData ?? this.nfcChipData,
        mrzScan: mrzScan ?? this.mrzScan,
        businessCountry: businessCountry ?? this.businessCountry,
        businessProduct: businessProduct ?? this.businessProduct,
        registrationNumber: registrationNumber ?? this.registrationNumber,
        registrationName: registrationName ?? this.registrationName,
      );

  KYCState clearError() => copyWith(error: null);
}
