import '../config/address_collection.dart';
import '../config/business.dart';
import '../config/business_application.dart';
import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/selfie_upload_wait.dart';
import '../services/api_service.dart';
import '../services/nfc_reader.dart';
import '../services/mrz_parser.dart';
import '../config/multi_id.dart';

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
  // The address flow: find it → confirm it → show it → commit it.
  // `addressCollection` is the PIN step and keeps its original wire name even
  // though it is now the second screen, so progress saved by older builds
  // restores cleanly. See config/address_flow.dart.
  addressSearch,
  addressCollection,
  addressEntrance,
  addressReview,
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
  final String? addressPhoto;

  const KYCMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
    this.proofOfAddress,
    this.addressPhoto,
  });

  KYCMediaIds copyWith({
    String? documentFront,
    String? documentBack,
    String? selfie,
    String? documentFrontVideo,
    String? documentBackVideo,
    String? livenessVideo,
    String? proofOfAddress,
    String? addressPhoto,
    // Removing an upload has to NULL the id, which `?? this` can't express —
    // same explicit-flag pattern as KYCState.clearSelectedIdType.
    bool clearProofOfAddress = false,
    bool clearAddressPhoto = false,
    // Retaking the selfie drops both its uploads (see KYCNotifier.clearSelfie).
    bool clearSelfie = false,
  }) =>
      KYCMediaIds(
        documentFront: documentFront ?? this.documentFront,
        documentBack: documentBack ?? this.documentBack,
        selfie: clearSelfie ? null : (selfie ?? this.selfie),
        documentFrontVideo: documentFrontVideo ?? this.documentFrontVideo,
        documentBackVideo: documentBackVideo ?? this.documentBackVideo,
        livenessVideo: clearSelfie ? null : (livenessVideo ?? this.livenessVideo),
        proofOfAddress:
            clearProofOfAddress ? null : (proofOfAddress ?? this.proofOfAddress),
        addressPhoto:
            clearAddressPhoto ? null : (addressPhoto ?? this.addressPhoto),
      );

  bool get hasAny =>
      documentFront != null ||
      documentBack != null ||
      selfie != null ||
      documentFrontVideo != null ||
      documentBackVideo != null ||
      livenessVideo != null ||
      proofOfAddress != null ||
      addressPhoto != null;
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

  /// The visitor's country from their IP — a DEFAULT, never evidence.
  final String? geoCountry;

  /// Whether the platform's forward address search is available. The address
  /// flow offers its search step only when it is; without it the applicant
  /// still places the pin by hand, which every failure path degrades to.
  final bool addressSearch;

  /// Which search backend answers: `autocomplete` or `basic`. Absent when
  /// [addressSearch] is false.
  final String? addressSearchMode;

  /// The framed Google-map picker page for a WebView (webview_flutter): our
  /// hosted /embed/map plus a signed APP grant. Null ⇒ the built-in OSM
  /// picker, which is also the fallback when the page never reports ready.
  final String? mapsFrameUrl;

  const ServerSdkConfig({
    required this.status,
    this.idTypes = const [],
    this.environment,
    this.error,
    this.statusCode,
    this.fatal = false,
    this.branding,
    this.geoCountry,
    this.addressSearch = false,
    this.addressSearchMode,
    this.mapsFrameUrl,
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

  /// The attempt SESSION this run is recorded under (`/session/start`). Null
  /// when minting failed — verifying is never conditional on it. Rides the
  /// /verify body so the verification adopts the session's id, and anchors the
  /// paid registry check at selection.
  final String? sessionId;

  /// The session's own hosted web page (see SessionStartResponse.url).
  final String? sessionUrl;

  /// What the register said about the company the applicant identified — the
  /// paid check run at SELECTION, so the officer list is already here by the
  /// time the key-people step asks for it. [checkedNumber] stops a re-check of
  /// the same company.
  final BusinessCheckState businessCheck;

  /// The country picked in the country-select step (multi-region flows). Null
  /// for single-country flows — the effective country then falls back to
  /// `config.country`. See `effectiveCountry` in step_order.dart.
  final String? selectedCountry;

  /// The declared country was GUESSED (the address scope's IP default, or a
  /// geocode adopted from the applicant's fix) rather than picked, so later
  /// evidence may correct it; an explicit pick clears it. Mirrors the web
  /// SDK's `countryAutoPicked`. See config/country_adoption.dart.
  final bool countryAutoPicked;

  /// The resolved definition for the picked ID type (curated or synthesized from
  /// the server config). Null until the user selects one.
  final IdTypeConfig? selectedIdType;
  final String? idNumber;

  /// Multi-ID: which check the applicant is on (0-based), and the ones already
  /// committed. A committed check keeps its local capture PATHS as well as its
  /// mediaIds, so stepping back into it restores what was captured.
  final int multiIdSlotIndex;
  final List<MultiIdSlot> multiIdSlots;
  final UserData? userData;
  final KYCMediaIds mediaIds;

  /// The captured selfie's base64 preview, kept CENTRALLY (the liveness
  /// screen's own state and the autoDispose liveness provider die on step
  /// change) so leaving the step and returning restores the review screen
  /// instead of re-running the whole gesture check. mediaIds.selfie beside it
  /// is the durable record; a restored session may hold only the mediaId.
  final String? selfieImage;

  /// The selfie upload's progress report, written by the liveness screen. The
  /// biometric scopes hand over before the upload lands (the review is off),
  /// so the submitted screen waits on THIS rather than on the screen's own
  /// state. See config/selfie_upload_wait.dart.
  final SelfieUploadState selfieUpload;
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

  /// The smart address the address-collection step gathered (pin + directions
  /// + optional device fix). On a KYB flow this is the business premises.
  /// Submitted under `address` on /verify. Null until placed.
  final AddressState? address;

  /// Local file path of the uploaded entrance photo, so the review step can
  /// show it. A display artefact: never serialised, and never restored (a
  /// resumed session holds the uploaded mediaId but not the bytes, so the
  /// entrance step renders its "photo added" placeholder instead).
  final String? addressPhotoPreview;

  /// The presence "how it works" primer was acknowledged this session.
  /// Session-local: never saved, never restored.
  final bool addressIntroSeen;

  /// The entrance step is showing the Street View framer, so the sheet header
  /// says so. Transient: never serialised, never restored.
  final bool addressEntranceFraming;

  /// Contact-verification proofs (email/phone OTP). Tokens are submitted under
  /// `contact` on /verify; the addresses are kept so a returning user sees the
  /// verified state.
  final String? emailToken;
  final String? emailAddress;
  final String? phoneToken;
  final String? phoneNumber;

  /// Channels whose proof the SERVER refused at submit (422
  /// contact_verification_required). Proofs are single-use and expire ~30
  /// minutes after the OTP check, but they ride session progress and are
  /// restored on resume, so a resumed attempt can carry a dead proof while the
  /// step still shows "verified". This routes the person back to re-verify
  /// instead of a retry that resubmits the same dead token forever;
  /// setContactProof clears its channel.
  final List<String> expiredContact;

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

  /// ISO 3166-2 registry region, for the four countries whose register is
  /// split by state or emirate (US/IN/CA/AE). Empty for everywhere else.
  /// Rides the search and the selection-time check.
  final String? businessSubdivisionCode;

  /// Dev/sandbox only: pins the canned outcome served instead of calling the
  /// register. Sent as `metadata.sandboxOutcome`; production ignores it.
  final String? businessSandboxOutcome;

  /// Dev/sandbox only: the address flow's Test-result pick (the web SDK's
  /// tabs). Sent as `metadata.sandboxOutcome`; production ignores it.
  final String? addressSandboxOutcome;

  /// Contact email for key-people invites (collected when the workflow emails
  /// verification links to full-KYC directors/owners).
  final String? businessContactEmail;

  /// Company profile (collectCompanyInfo fields) — echoed on the org's webhook
  /// and address-matched against the registry record server-side. The last
  /// five are registry facts the applicant STATES (their own answer, which the
  /// server compares against the register — where the two differ is the
  /// finding).
  final String? businessAddress;
  final String? businessEmail;
  final String? businessPhone;
  final String? businessWebsite;
  final String? businessDateOfIncorporation;
  final String? businessTaxId;
  final String? businessVatNumber;
  final String? businessCompanyType;
  final String? businessNatureOfBusiness;

  /// Applicant-declared directors & owners (business-key-people step).
  final List<KeyPersonEntry> keyPeople;

  /// The FATF fallback, attested: some companies genuinely have no natural
  /// person who qualifies as a UBO (listed companies, complex trusts, nominee
  /// arrangements). Without it the applicant's only moves are to stall or to
  /// invent one. An attestation the org can branch on, never a verdict — and
  /// the registry lookup still says whatever it says.
  final bool uboUnidentifiable;

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
    this.sessionId,
    this.sessionUrl,
    this.businessCheck = const BusinessCheckState(),
    this.selectedCountry,
    this.countryAutoPicked = false,
    this.selectedIdType,
    this.idNumber,
    this.multiIdSlotIndex = 0,
    this.multiIdSlots = const [],
    this.userData,
    this.mediaIds = const KYCMediaIds(),
    this.selfieImage,
    this.selfieUpload = kIdleSelfieUpload,
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
    this.address,
    this.addressPhotoPreview,
    this.addressIntroSeen = false,
    this.addressEntranceFraming = false,
    this.emailToken,
    this.emailAddress,
    this.phoneToken,
    this.phoneNumber,
    this.expiredContact = const [],
    this.nfcChipData,
    this.mrzScan,
    this.businessCountry,
    this.businessProduct,
    this.registrationNumber,
    this.registrationName,
    this.businessSubdivisionCode,
    this.businessSandboxOutcome,
    this.addressSandboxOutcome,
    this.businessContactEmail,
    this.businessAddress,
    this.businessEmail,
    this.businessPhone,
    this.businessWebsite,
    this.businessDateOfIncorporation,
    this.businessTaxId,
    this.businessVatNumber,
    this.businessCompanyType,
    this.businessNatureOfBusiness,
    this.keyPeople = const [],
    this.uboUnidentifiable = false,
    this.businessDocuments = const [],
    this.applicantRole,
    this.applicantName,
    this.applicantKeyPersonIndex,
  });

  KYCState copyWith({
    KYCStep? currentStep,
    String? sessionId,
    String? sessionUrl,
    BusinessCheckState? businessCheck,
    String? selectedCountry,
    bool? countryAutoPicked,
    IdTypeConfig? selectedIdType,
    String? idNumber,
    int? multiIdSlotIndex,
    List<MultiIdSlot>? multiIdSlots,
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
    AddressState? address,
    // Starting the address over must null the pin, which `?? this` cannot
    // express — the same explicit-flag pattern as clearSelectedIdType.
    bool clearAddress = false,
    String? addressPhotoPreview,
    bool clearAddressPhotoPreview = false,
    bool? addressIntroSeen,
    bool? addressEntranceFraming,
    String? emailToken,
    // Explicit flags: null tokens cannot be set via `?? this` (the
    // clearSelectedIdType pattern) — used by submit recovery.
    bool clearEmailToken = false,
    String? emailAddress,
    String? phoneToken,
    bool clearPhoneToken = false,
    String? phoneNumber,
    NfcChipData? nfcChipData,
    MrzScan? mrzScan,
    String? businessCountry,
    String? businessProduct,
    String? registrationNumber,
    String? registrationName,
    String? businessSubdivisionCode,
    String? businessSandboxOutcome,
    String? addressSandboxOutcome,
    String? businessContactEmail,
    String? businessAddress,
    String? businessEmail,
    String? businessPhone,
    String? businessWebsite,
    String? businessDateOfIncorporation,
    String? businessTaxId,
    String? businessVatNumber,
    String? businessCompanyType,
    String? businessNatureOfBusiness,
    List<KeyPersonEntry>? keyPeople,
    bool? uboUnidentifiable,
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
    bool clearNfcChipData = false,
    // Removing the PoA upload also clears the kind it was labelled with.
    bool clearPoaDocumentType = false,
    String? selfieImage,
    SelfieUploadState? selfieUpload,
    // Retake: copyWith can't null a field via `?? this`.
    bool clearSelfieImage = false,
    List<String>? expiredContact,
  }) =>
      KYCState(
        currentStep: currentStep ?? this.currentStep,
        sessionId: sessionId ?? this.sessionId,
      sessionUrl: sessionUrl ?? this.sessionUrl,
        businessCheck: businessCheck ?? this.businessCheck,
        selectedCountry: selectedCountry ?? this.selectedCountry,
        countryAutoPicked: countryAutoPicked ?? this.countryAutoPicked,
        selectedIdType:
            clearSelectedIdType ? null : (selectedIdType ?? this.selectedIdType),
        idNumber: clearSelectedIdType ? null : (idNumber ?? this.idNumber),
        multiIdSlotIndex: multiIdSlotIndex ?? this.multiIdSlotIndex,
        multiIdSlots: multiIdSlots ?? this.multiIdSlots,
        userData: userData ?? this.userData,
        mediaIds: mediaIds ?? this.mediaIds,
        selfieImage: clearSelfieImage ? null : (selfieImage ?? this.selfieImage),
        // A retake drops the old upload's record with the selfie.
        selfieUpload: clearSelfieImage ? kIdleSelfieUpload : (selfieUpload ?? this.selfieUpload),
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
        address: clearAddress ? null : (address ?? this.address),
        addressPhotoPreview: clearAddressPhotoPreview
            ? null
            : (addressPhotoPreview ?? this.addressPhotoPreview),
        addressIntroSeen: addressIntroSeen ?? this.addressIntroSeen,
        addressEntranceFraming:
            addressEntranceFraming ?? this.addressEntranceFraming,
        emailToken: clearEmailToken ? null : (emailToken ?? this.emailToken),
        emailAddress: emailAddress ?? this.emailAddress,
        phoneToken: clearPhoneToken ? null : (phoneToken ?? this.phoneToken),
        phoneNumber: phoneNumber ?? this.phoneNumber,
        expiredContact: expiredContact ?? this.expiredContact,
        nfcChipData: clearNfcChipData ? null : (nfcChipData ?? this.nfcChipData),
        mrzScan: mrzScan ?? this.mrzScan,
        businessCountry: businessCountry ?? this.businessCountry,
        businessProduct: businessProduct ?? this.businessProduct,
        registrationNumber: registrationNumber ?? this.registrationNumber,
        registrationName: registrationName ?? this.registrationName,
        businessSubdivisionCode:
            businessSubdivisionCode ?? this.businessSubdivisionCode,
        businessSandboxOutcome:
            businessSandboxOutcome ?? this.businessSandboxOutcome,
        addressSandboxOutcome:
            addressSandboxOutcome ?? this.addressSandboxOutcome,
        businessContactEmail:
            businessContactEmail ?? this.businessContactEmail,
        businessAddress: businessAddress ?? this.businessAddress,
        businessEmail: businessEmail ?? this.businessEmail,
        businessPhone: businessPhone ?? this.businessPhone,
        businessWebsite: businessWebsite ?? this.businessWebsite,
        businessDateOfIncorporation:
            businessDateOfIncorporation ?? this.businessDateOfIncorporation,
        businessTaxId: businessTaxId ?? this.businessTaxId,
        businessVatNumber: businessVatNumber ?? this.businessVatNumber,
        businessCompanyType: businessCompanyType ?? this.businessCompanyType,
        businessNatureOfBusiness:
            businessNatureOfBusiness ?? this.businessNatureOfBusiness,
        keyPeople: keyPeople ?? this.keyPeople,
        uboUnidentifiable: uboUnidentifiable ?? this.uboUnidentifiable,
        businessDocuments: businessDocuments ?? this.businessDocuments,
        applicantRole: applicantRole ?? this.applicantRole,
        applicantName: applicantName ?? this.applicantName,
        applicantKeyPersonIndex: clearApplicantKeyPersonIndex
            ? null
            : (applicantKeyPersonIndex ?? this.applicantKeyPersonIndex),
      );

  KYCState clearError() => copyWith(error: null);
}

/// The registry check run when the applicant confirms their company.
///
/// `skipped` and `limit_reached` are normal outcomes, not failures: the
/// organisation could not be charged (or this application has spent its lookup
/// budget), so the flow carries on and the check happens at submission instead.
/// Mirrors the web SDK's BusinessCheckState — keep the two in lockstep.
class BusinessCheckState {
  /// 'idle' | 'checking' | 'found' | 'not_found' | 'skipped' | 'unavailable'
  /// | 'limit_reached'
  final String status;

  /// What the register holds, when it answered.
  final BusinessCompanyRecord? company;

  /// The officers on file — what makes the key-people question a confirmation.
  final List<RegistryOfficer> officers;

  /// Which company was checked (normalised uppercase), so a changed number
  /// re-runs it and a repeat press does not pay to be told again.
  final String? checkedNumber;

  /// Which form fields the REGISTER filled, as opposed to the applicant
  /// (canonical business field keys, e.g. 'registrationName', 'address').
  ///
  /// Kept so that changing which company this is can clear exactly those and
  /// nothing else. Without it, switching company left the previous register's
  /// address and email sitting in the form under the new company's name — and
  /// because the prefill only writes into empty fields, those leftovers also
  /// blocked the new register's real values from ever landing.
  final List<String> prefilled;

  const BusinessCheckState({
    this.status = 'idle',
    this.company,
    this.officers = const [],
    this.checkedNumber,
    this.prefilled = const [],
  });

  BusinessCheckState copyWith({
    String? status,
    BusinessCompanyRecord? company,
    List<RegistryOfficer>? officers,
    String? checkedNumber,
    List<String>? prefilled,
    bool clearCompany = false,
  }) =>
      BusinessCheckState(
        status: status ?? this.status,
        company: clearCompany ? null : (company ?? this.company),
        officers: officers ?? this.officers,
        checkedNumber: checkedNumber ?? this.checkedNumber,
        prefilled: prefilled ?? this.prefilled,
      );
}

/// What `checkBusiness` resolves with. Only a definitive "not on the register"
/// stops the flow; the company record is handed back for the prefill.
typedef BusinessCheckResult = ({bool canContinue, BusinessCompanyRecord? company});
