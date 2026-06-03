import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../services/api_service.dart';

// ─── KYC flow step ────────────────────────────────────────────────────────────
//
// 5-step flow paths:
//   • Document-required IDs:  consent → idType → documentCapture → liveness → submitted
//   • Number-only IDs:        consent → idType → idInput         → liveness → submitted

enum KYCStep {
  consent,
  idType,
  documentCapture,
  idInput,
  liveness,
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

  const KYCMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
  });

  KYCMediaIds copyWith({
    String? documentFront,
    String? documentBack,
    String? selfie,
    String? documentFrontVideo,
    String? documentBackVideo,
    String? livenessVideo,
  }) =>
      KYCMediaIds(
        documentFront: documentFront ?? this.documentFront,
        documentBack: documentBack ?? this.documentBack,
        selfie: selfie ?? this.selfie,
        documentFrontVideo: documentFrontVideo ?? this.documentFrontVideo,
        documentBackVideo: documentBackVideo ?? this.documentBackVideo,
        livenessVideo: livenessVideo ?? this.livenessVideo,
      );

  bool get hasAny =>
      documentFront != null ||
      documentBack != null ||
      selfie != null ||
      documentFrontVideo != null ||
      documentBackVideo != null ||
      livenessVideo != null;
}

// ─── Server-driven SDK config (fetched from /api/kyc/config) ─────────────────

enum ServerConfigStatus { loading, ready, error }

class ServerSdkConfig {
  final ServerConfigStatus status;
  final List<SdkConfigIdType> idTypes;
  final String? environment;
  final String? error;

  /// Org branding (logo, name, color) returned by /api/kyc/config. Consumed
  /// when the consumer sets `appearance.logo = 'default'`.
  final SdkConfigBranding? branding;

  const ServerSdkConfig({
    required this.status,
    this.idTypes = const [],
    this.environment,
    this.error,
    this.branding,
  });

  static const ServerSdkConfig loading =
      ServerSdkConfig(status: ServerConfigStatus.loading);

  /// Returns the per-ID feature flags for the given (country, idType), or
  /// null if the ID isn't in the access list (or config hasn't loaded yet).
  SdkIdTypeFeatures? featuresFor(String country, String idType) {
    for (final row in idTypes) {
      if (row.country == country && row.idType == idType) return row.features;
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
  final IdType? selectedIdType;
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

  /// Server-driven config: which IDs the org may verify and which SDK
  /// features apply per ID. Fetched once from /api/kyc/config on mount.
  final ServerSdkConfig serverConfig;

  const KYCState({
    this.currentStep = KYCStep.consent,
    this.selectedIdType,
    this.idNumber,
    this.userData,
    this.mediaIds = const KYCMediaIds(),
    this.submissionResult,
    this.error,
    this.isLoading = false,
    this.documentScanPhase = 'front',
    this.docReviewPhase = 'camera',
    this.serverConfig = ServerSdkConfig.loading,
  });

  KYCState copyWith({
    KYCStep? currentStep,
    IdType? selectedIdType,
    String? idNumber,
    UserData? userData,
    KYCMediaIds? mediaIds,
    KYCSubmissionResult? submissionResult,
    String? error,
    bool? isLoading,
    String? documentScanPhase,
    String? docReviewPhase,
    ServerSdkConfig? serverConfig,
  }) =>
      KYCState(
        currentStep: currentStep ?? this.currentStep,
        selectedIdType: selectedIdType ?? this.selectedIdType,
        idNumber: idNumber ?? this.idNumber,
        userData: userData ?? this.userData,
        mediaIds: mediaIds ?? this.mediaIds,
        submissionResult: submissionResult ?? this.submissionResult,
        error: error ?? this.error,
        isLoading: isLoading ?? this.isLoading,
        documentScanPhase: documentScanPhase ?? this.documentScanPhase,
        docReviewPhase: docReviewPhase ?? this.docReviewPhase,
        serverConfig: serverConfig ?? this.serverConfig,
      );

  KYCState clearError() => copyWith(error: null);
}
