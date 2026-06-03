/// Myaza KYC SDK — public API barrel file.
///
/// Import this single file to access everything:
///   import 'package:kyc_sdk_flutter/kyc_sdk_flutter.dart';
library kyc_sdk_flutter;

// Config
export 'src/config/kyc_config.dart'
    show
        KYCEnvironment,
        MyazaThemeMode,
        MyazaKYCAppearance,
        KYCConsentContent,
        LivenessConfig,
        UserData,
        MyazaKYCConfig,
        KYCSubmission,
        KYCError;

export 'src/config/id_types.dart'
    show
        Country,
        IdType,
        ScanSides,
        IdTypeConfig,
        kIdTypesByCountry,
        getIdTypesForCountry,
        getIdTypeConfig;

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
