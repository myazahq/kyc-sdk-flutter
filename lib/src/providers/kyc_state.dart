import '../config/business.dart';
import '../config/business_application.dart';
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
  // Business (KYB) application section. businessDetails is always present in a
  // business flow; the rest are added only when the workflow configures them.
  businessDetails,
  businessKeyPeople,
  businessDocuments,
  // The applicant declares their role, then runs the ORDINARY individual
  // capture leg (idType → capture → liveness) for their own identity.
  applicantRole,
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
    // Removing an upload has to NULL the id, which `?? this` can't express —
    // same explicit-flag pattern as KYCState.clearSelectedIdType.
    bool clearProofOfAddress = false,
  }) =>
      KYCMediaIds(
        documentFront: documentFront ?? this.documentFront,
        documentBack: documentBack ?? this.documentBack,
        selfie: selfie ?? this.selfie,
        documentFrontVideo: documentFrontVideo ?? this.documentFrontVideo,
        documentBackVideo: documentBackVideo ?? this.documentBackVideo,
        livenessVideo: livenessVideo ?? this.livenessVideo,
        proofOfAddress:
            clearProofOfAddress ? null : (proofOfAddress ?? this.proofOfAddress),
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

  /// Per-person verification links the server minted for full-KYC key people
  /// (KYB submissions). The success screen renders them with copy buttons so
  /// the applicant can send each person their link immediately.
  final List<KeyPersonInvite> keyPeopleInvites;
  final String? error;
  final bool isLoading;
  final String documentScanPhase; // 'front' | 'back' | 'complete'

  /// Review phase communicated by DocumentCaptureScreen so the parent
  /// (_KycFlowWidget) can update the step header title dynamically.
  /// Values: 'camera' | 'front_preview' | 'camera_back' | 'review'
  final String docReviewPhase;

  /// What the contact step is currently doing, so _KycFlowWidget can caption it
  /// — the header is rendered by the shell and cannot see the screen's state.
  /// Empty means "not on a contact step". Mirrors docReviewPhase.
  /// Channel: '' | 'email' | 'phone'. Destination is set only once a code is
  /// actually out, which is what flips the header from promise to instruction.
  final String contactChannel;
  final String contactVia;
  final String contactDestination;

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

  /// Contact email for key-people invites (collected when the workflow emails
  /// verification links to full-KYC directors/owners).
  final String? businessContactEmail;

  /// Company profile (collectCompanyInfo fields) — echoed on the org's webhook
  /// and address-matched against the registry record server-side.
  final String? businessAddress;
  final String? businessEmail;
  final String? businessPhone;
  final String? businessWebsite;

  /// Applicant-declared directors & owners (business-key-people step).
  final List<KeyPersonEntry> keyPeople;

  /// Uploaded supporting documents (business-documents step).
  final List<BusinessDocumentUpload> businessDocuments;

  /// The applicant's declared role + optional name (applicant-role step). Their
  /// own identity verification runs as a second, ordinary individual
  /// submission linked back via `metadata.userId`.
  final ApplicantRole? applicantRole;
  final String? applicantName;

  /// The applicant picked THEMSELVES from the entered key people (index into
  /// [keyPeople]). Null = they're someone else / nothing picked. The flagged
  /// entry is merged server-side with the applicant row — one person, one
  /// KYC, one screening, no duplicate invite.
  final int? applicantKeyPersonIndex;

  const KYCState({
    this.currentStep = KYCStep.consent,
    this.selectedCountry,
    this.selectedIdType,
    this.idNumber,
    this.userData,
    this.mediaIds = const KYCMediaIds(),
    this.submissionResult,
    this.keyPeopleInvites = const [],
    this.error,
    this.isLoading = false,
    this.documentScanPhase = 'front',
    this.docReviewPhase = 'camera',
    this.contactChannel = '',
    this.contactVia = '',
    this.contactDestination = '',
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
    this.businessContactEmail,
    this.businessAddress,
    this.businessEmail,
    this.businessPhone,
    this.businessWebsite,
    this.keyPeople = const [],
    this.businessDocuments = const [],
    this.applicantRole,
    this.applicantName,
    this.applicantKeyPersonIndex,
  });

  KYCState copyWith({
    KYCStep? currentStep,
    String? selectedCountry,
    IdTypeConfig? selectedIdType,
    String? idNumber,
    UserData? userData,
    KYCMediaIds? mediaIds,
    KYCSubmissionResult? submissionResult,
    List<KeyPersonInvite>? keyPeopleInvites,
    String? error,
    bool? isLoading,
    String? documentScanPhase,
    String? docReviewPhase,
    String? contactChannel,
    String? contactVia,
    String? contactDestination,
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
    String? businessContactEmail,
    String? businessAddress,
    String? businessEmail,
    String? businessPhone,
    String? businessWebsite,
    List<KeyPersonEntry>? keyPeople,
    List<BusinessDocumentUpload>? businessDocuments,
    ApplicantRole? applicantRole,
    String? applicantName,
    int? applicantKeyPersonIndex,
    // "I'm not one of these people" — copyWith can't null a field via
    // `?? this`, so this explicit flag clears the self-selection.
    bool clearApplicantKeyPersonIndex = false,
    // Picking a new country invalidates the selected ID; copyWith can't null a
    // field via `?? this`, so this explicit flag clears it (and its number).
    bool clearSelectedIdType = false,
    // Removing the PoA upload also clears the kind it was labelled with.
    bool clearPoaDocumentType = false,
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
        keyPeopleInvites: keyPeopleInvites ?? this.keyPeopleInvites,
        error: error ?? this.error,
        isLoading: isLoading ?? this.isLoading,
        documentScanPhase: documentScanPhase ?? this.documentScanPhase,
        docReviewPhase: docReviewPhase ?? this.docReviewPhase,
        contactChannel: contactChannel ?? this.contactChannel,
        contactVia: contactVia ?? this.contactVia,
        contactDestination: contactDestination ?? this.contactDestination,
        immersiveCapture: immersiveCapture ?? this.immersiveCapture,
        serverConfig: serverConfig ?? this.serverConfig,
        questionnaireAnswers:
            questionnaireAnswers ?? this.questionnaireAnswers,
        integrity: integrity ?? this.integrity,
        poaDocumentType:
            clearPoaDocumentType ? null : (poaDocumentType ?? this.poaDocumentType),
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
        businessContactEmail:
            businessContactEmail ?? this.businessContactEmail,
        businessAddress: businessAddress ?? this.businessAddress,
        businessEmail: businessEmail ?? this.businessEmail,
        businessPhone: businessPhone ?? this.businessPhone,
        businessWebsite: businessWebsite ?? this.businessWebsite,
        keyPeople: keyPeople ?? this.keyPeople,
        businessDocuments: businessDocuments ?? this.businessDocuments,
        applicantRole: applicantRole ?? this.applicantRole,
        applicantName: applicantName ?? this.applicantName,
        applicantKeyPersonIndex: clearApplicantKeyPersonIndex
            ? null
            : (applicantKeyPersonIndex ?? this.applicantKeyPersonIndex),
      );

  KYCState clearError() => copyWith(error: null);
}
