/// Myaza KYC SDK — public API barrel file.
///
/// Import this single file to access everything:
///   import 'package:kyc_sdk_flutter/kyc_sdk_flutter.dart';
library kyc_sdk_flutter;

// Config
export 'src/config/kyc_config.dart'
    show
        MyazaProgressStyle,
        MyazaThemeMode,
        MyazaKYCAppearance,
        KYCConsentContent,
        KYCSuccessContent,
        LivenessConfig,
        VoiceGuidanceConfig,
        UserData,
        WorkflowCountryOption,
        MyazaKYCConfig,
        KYCSubmission,
        KYCError;

// The verdict callback payload (a flow that waits for its result in the app).
export 'src/config/kyc_result.dart' show KYCResult;

// The biometric scopes' flow options (selfie review, where the verdict lands,
// the Done button), resolved the same way on the server and every SDK.
export 'src/config/biometric_options.dart'
    show
        BiometricFlowConfig,
        BiometricFlowOptions,
        BiometricFlowConfigX,
        biometricFlowOptions,
        showsSelfieReview,
        waitsForResult,
        showsDoneButton;
// The org's own words on the biometric screens (loading + the two verdicts),
// resolved with the tokens filled the way the consent and success copy are.
export 'src/config/biometric_copy.dart'
    show
        BiometricCopy,
        BiometricCopyText,
        BiometricCopyX,
        ResolvedBiometricCopy,
        biometricCopyFor;
export 'src/config/copy_tokens.dart' show fillCopyTokens;

export 'src/config/id_types.dart'
    show
        ScanSides,
        IdTypeConfig,
        kCuratedIdTypes,
        countryLabel,
        curatedIdTypesForCountry,
        curatedIdType,
        resolveIdTypeDefinition;

export 'src/config/country_names.g.dart' show kCountryNames;

export 'src/config/questionnaire.dart'
    show
        QuestionnaireFieldType,
        QuestionnaireOption,
        QuestionnaireField,
        QuestionnaireConfig;

export 'src/config/proof_of_address.dart'
    show PoaDocumentType, ProofOfAddressConfig;

export 'src/config/address_collection.dart'
    show
        AddressCollectionConfig,
        AddressState,
        AddressPickedAt,
        AddressStreetView,
        addressPayload;

// The address wire shapes: the breakdown a collected address holds onto, and
// what the four address endpoints answer with.
export 'src/services/api_service.dart'
    show
        AddressParts,
        AddressReverseResult,
        AddressSearchHit,
        PlaceSuggestion,
        ResolvedPlace;

// The address flow as pure rules — a cross-SDK mirror of the web and RN
// models. Exported so a host can reason about the flow it configured.
export 'src/config/address_flow.dart'
    show
        AddressFlowOptions,
        addressFlowOptions,
        addressFlowSteps,
        addressVendorsStubbed,
        kSampleAddressLine,
        nextAddressStep,
        prevAddressStep,
        metersBetween,
        shouldAskLabelDecision,
        displayAddressLine,
        kPinEpsilon,
        kKeepPickedLabelRadiusM,
        kLabelPromptMinMoveM,
        kReverseDebounce;

// Presence verification (Address Intelligence Phase 2): the foreground
// reporter the HOST APP calls on app open, plus the on-device pin store.
export 'src/presence/presence_reporter.dart'
    show MyazaAddressPresence, PresenceReportReason, PresenceReportResult;
// savePresencePin is the org-side handoff for STANDALONE address
// verification: when capture happened on a hosted web link (or the org's own
// backend already holds the address), the host app hands the SDK the pin so
// the foreground and background presence tiers can run.
export 'src/presence/presence_store.dart' show clearPresencePin, savePresencePin;
export 'src/presence/background_presence.dart'
    show
        BackgroundPresenceReason,
        EnableBackgroundResult,
        MyazaBackgroundPresence,
        kGeofenceRadiusMeters;
// The Android foreground-service tier (the OkHi reliability move): a
// persistent notification keeps the process alive on phones whose battery
// managers drop geofence transitions. Opt-in; the host words the notification
// and declares the service in its own manifest.
export 'src/presence/foreground_presence.dart'
    show
        EnableForegroundServiceResult,
        ForegroundServiceReason,
        MyazaPresenceService,
        PresenceNotification;
export 'src/presence/presence_status.dart'
    show
        PresencePermission,
        PresenceSettingsTarget,
        PresenceStatus,
        PresenceTier,
        openLocationSettings,
        presenceStatus;
export 'src/presence/presence_tier.dart'
    show PresenceTierInputs, resolvePresenceTier;

export 'src/config/contact_verification.dart'
    show OtpInputStyle, EmailVerificationConfig, PhoneVerificationConfig;

export 'src/config/nfc_config.dart' show NfcConfig;

export 'src/config/business.dart'
    show
        BusinessProductInput,
        BusinessProduct,
        kBusinessProducts,
        kDefaultBusinessProduct,
        businessProduct,
        isValidContactEmail,
        CompanyInfoField,
        CompanyInfoMode,
        KeyPersonRole,
        ApplicantRole,
        KeyPeopleLevel,
        keyPersonRoleFromKey,
        kBusinessDocumentLabels,
        businessDocumentLabel,
        WorkflowKeyPeopleConfig,
        WorkflowBusinessDocumentType,
        WorkflowBusinessDocumentsConfig,
        WorkflowBusinessApplicantConfig,
        WorkflowBusinessConfig;

// The KYB application section — which steps a business workflow adds beyond the
// registration details, and the row/payload models those steps collect.
export 'src/config/business_application.dart'
    show
        kMaxKeyPeopleRows,
        hasKeyPeopleCollection,
        hasBusinessDocumentsStep,
        hasApplicantVerification,
        keyPeopleMinEntries,
        resolveBusinessDocumentTypes,
        ResolvedBusinessDocumentType,
        KeyPersonEntry,
        KeyPersonOwnerEntry,
        looksCorporate,
        BusinessDocumentUpload,
        keyPeoplePayload;

// NFC chip reader — the interface + types are public so hosts can inject a
// custom/stub reader via `nfcChipReaderOverride` (tests, or a different eMRTD lib).
export 'src/services/nfc_reader.dart'
    show
        NfcMrzKey,
        NfcChipData,
        NfcReadException,
        NfcChipReader,
        nfcChipReaderOverride;

// Validators — useful for callers who want to pre-validate before calling show()
export 'src/services/validators.dart'
    show
        ValidationResult,
        validateIdNumber,
        maskIdNumber;

export 'src/config/theme.dart'
    show
        MyazaColors,
        MyazaTypography,
        MyazaRadius,
        MyazaSpacing,
        MyazaSizing;

// Liveness types
export 'src/liveness/liveness_types.dart'
    show
        LivenessChallenge,
        LivenessPhase,
        ChallengeConfig,
        kDefaultChallengePool;

// Face detection — real on-device detection ships in-package and is the default
// (iOS: Apple Vision · Android: ML Kit native Gradle; no GoogleMLKit pod, so
// arm64 iOS-simulator builds work). Hosts need not register anything;
// registerFaceDetectorFactory() is an optional override (custom detector/tests).
export 'src/liveness/face_detection.dart'
    show
        LivenessFaceData,
        FaceDetectorService,
        NativeFaceDetectorService,
        StubFaceDetectorService,
        registerFaceDetectorFactory,
        createFaceDetectorService,
        hasFaceDetectorFactory;

// State
export 'src/providers/kyc_state.dart'
    show
        KYCStep,
        KYCMediaIds,
        KYCSubmissionResult,
        KYCState;

// Widgets
export 'src/widgets/myaza_button.dart' show MyazaButton, MyazaButtonVariant;
export 'src/widgets/myaza_input.dart' show MyazaInput;
export 'src/widgets/myaza_card.dart' show MyazaCard;
export 'src/widgets/myaza_alert.dart' show MyazaAlert, MyazaAlertVariant;
export 'src/widgets/step_header.dart' show StepHeader;
export 'src/widgets/kyc_bottom_sheet.dart' show KycBottomSheet;

// Entry widget (MyazaKYC.show + MyazaKYCWidget)
export 'src/widgets/myaza_kyc_widget.dart' show MyazaKYC, MyazaKYCWidget;

// Returning-user face re-authentication (MyazaBiometricAuth.show) + its wire
// shapes.
export 'src/widgets/myaza_biometric_auth.dart' show MyazaBiometricAuth;
export 'src/services/api_service.dart'
    show BiometricAuthResponse, BiometricStatusResponse;
