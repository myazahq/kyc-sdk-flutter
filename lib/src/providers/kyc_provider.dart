import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../services/api_service.dart';
import '../services/device_metadata_service.dart';
import '../services/retry.dart';
import '../services/validators.dart';
import '../utils/resolve_url.dart';
import 'kyc_state.dart';

part 'kyc_provider.g.dart';

// ─── Config provider ─────────────────────────────────────────────────────────
// Override this in ProviderScope when launching the KYC flow:
//   ProviderScope(
//     overrides: [kycConfigProvider.overrideWithValue(config)],
//     child: ...,
//   )

@Riverpod(keepAlive: true)
MyazaKYCConfig kycConfig(Ref ref) {
  throw StateError(
    'kycConfigProvider must be overridden in ProviderScope before use.',
  );
}

// ─── Shared UUID generator ────────────────────────────────────────────────────

const _uuid = Uuid();

// ─── KYC flow notifier ────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class KYCNotifier extends _$KYCNotifier {
  @override
  KYCState build() {
    // Kick off the /api/kyc/config fetch asynchronously. The state starts in
    // ServerConfigStatus.loading and the screens render placeholders until
    // this resolves. Errors fall through to status: error and the SDK falls
    // back to the consumer's `idTypes` prop (server still 403s anything
    // actually disabled, so this is at worst as restrictive as the server).
    Future.microtask(_loadServerConfig);
    return const KYCState();
  }

  Future<void> _loadServerConfig() async {
    try {
      final response = await api.config();
      state = state.copyWith(
        serverConfig: ServerSdkConfig(
          status: ServerConfigStatus.ready,
          idTypes: response.idTypes,
          environment: response.environment,
          branding: response.branding,
        ),
      );
    } catch (err) {
      final described = _describeConfigError(err);
      state = state.copyWith(
        serverConfig: ServerSdkConfig(
          status: ServerConfigStatus.error,
          error: described.message,
          statusCode: described.statusCode,
          fatal: described.fatal,
        ),
      );
    }
  }

  // Maps a config-load failure to a user-facing message. Auth failures
  // (401/403) are "fatal": the API key is wrong or not permitted, so the flow
  // can't run and the modal blocks on a clear error rather than silently
  // degrading. Other failures (network blips, 5xx) are non-fatal — the flow
  // falls back to the prop ID-type list and any real problem resurfaces at the
  // verify step.
  ({String message, int? statusCode, bool fatal}) _describeConfigError(
    Object err,
  ) {
    if (err is KYCApiException) {
      if (err.statusCode == 401) {
        return (
          message: 'Invalid API key. Please check the API key configured in the SDK.',
          statusCode: 401,
          fatal: true,
        );
      }
      if (err.statusCode == 403) {
        return (
          message: err.message ??
              'This API key is not permitted to use the verification SDK.',
          statusCode: 403,
          fatal: true,
        );
      }
      if (err.statusCode >= 500) {
        return (
          message:
              'A server error occurred while loading verification settings. Please try again.',
          statusCode: err.statusCode,
          fatal: false,
        );
      }
      return (
        message: err.message ?? err.error,
        statusCode: err.statusCode,
        fatal: false,
      );
    }
    return (message: err.toString(), statusCode: null, fatal: false);
  }

  // ── Config + service helpers ───────────────────────────────────────────────

  MyazaKYCConfig get _config => ref.read(kycConfigProvider);

  KYCApiService get api => KYCApiService(
        baseUrl: resolveBaseUrl(_config.apiKey, devUrl: _config.devUrl),
        apiKey: _config.apiKey,
      );

  /// Whether the currently selected ID type requires document capture,
  /// accounting for the global `enableDocumentCapture` flag in config.
  bool get _selectedRequiresCapture {
    final idType = state.selectedIdType;
    if (idType == null) return false;
    final cfg = getIdTypeConfig(_config.country, idType);
    return (cfg?.requiresDocumentCapture ?? false) &&
        _config.enableDocumentCapture;
  }

  /// Whether liveness should run for the currently selected ID. Server-driven
  /// per-ID flag wins; falls back to the consumer's `enableLiveness` /
  /// `enableSelfie` props when the server config hasn't loaded.
  bool get _livenessEnabledForSelectedId {
    if (!_config.enableLiveness || !_config.enableSelfie) return false;
    final idType = state.selectedIdType;
    if (idType == null) return true;
    final cfg = getIdTypeConfig(_config.country, idType);
    if (cfg == null) return true;
    final features =
        state.serverConfig.featuresFor(_config.country.name, cfg.key);
    if (features == null) return true; // server config not loaded — assume on
    return features.livenessCheck;
  }

  // ── Step navigation ────────────────────────────────────────────────────────

  /// Advances to the next step in the KYC flow.
  /// Two flow paths (5 steps each):
  ///   • Document-required IDs:  consent → idType → documentCapture → liveness → submitted
  ///   • Number-only IDs:        consent → idType → idInput         → liveness → submitted
  /// If liveness is disabled in config, the liveness step is skipped.
  void nextStep() {
    final next = _nextStepAfter(state.currentStep);
    if (next != null) {
      state = state.copyWith(currentStep: next);
    }
  }

  KYCStep? _nextStepAfter(KYCStep current) {
    return switch (current) {
      KYCStep.consent => KYCStep.idType,
      KYCStep.idType => _selectedRequiresCapture
          ? KYCStep.documentCapture
          : KYCStep.idInput,
      KYCStep.documentCapture =>
          _livenessEnabledForSelectedId ? KYCStep.liveness : KYCStep.submitted,
      KYCStep.idInput =>
          _livenessEnabledForSelectedId ? KYCStep.liveness : KYCStep.submitted,
      KYCStep.liveness => KYCStep.submitted,
      KYCStep.submitted => null, // terminal step
    };
  }

  /// Goes back one step, skipping document capture if it was skipped forward.
  void previousStep() {
    final prev = _prevStepBefore(state.currentStep);
    if (prev != null) {
      state = state.copyWith(currentStep: prev);
    }
  }

  KYCStep? _prevStepBefore(KYCStep current) {
    return switch (current) {
      KYCStep.consent => null, // already at start
      KYCStep.idType => KYCStep.consent,
      KYCStep.documentCapture => KYCStep.idType,
      KYCStep.idInput => KYCStep.idType,
      KYCStep.liveness => _selectedRequiresCapture
          ? KYCStep.documentCapture
          : KYCStep.idInput,
      KYCStep.submitted => null, // terminal — no going back after submission
    };
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  void setIdType(IdType idType) {
    state = state.copyWith(
      selectedIdType: idType,
      // Clear any previously captured document state when switching ID type
      documentScanPhase: 'front',
      docReviewPhase: 'camera',
    );
  }

  /// Called by DocumentCaptureScreen to keep the parent step header in sync.
  void setDocReviewPhase(String phase) {
    state = state.copyWith(docReviewPhase: phase);
  }

  void setIdNumber(String idNumber) {
    state = state.copyWith(idNumber: idNumber.trim());
  }

  /// Stores the mediaId returned by /api/kyc/upload for the given [type].
  /// [type] must be one of: 'documentFront', 'documentBack', 'selfie',
  /// 'documentFrontVideo', 'documentBackVideo', 'livenessVideo'.
  void setMediaId(String type, String mediaId) {
    final current = state.mediaIds;
    final updated = switch (type) {
      'documentFront'      => current.copyWith(documentFront: mediaId),
      'documentBack'       => current.copyWith(documentBack: mediaId),
      'selfie'             => current.copyWith(selfie: mediaId),
      'documentFrontVideo' => current.copyWith(documentFrontVideo: mediaId),
      'documentBackVideo'  => current.copyWith(documentBackVideo: mediaId),
      'livenessVideo'      => current.copyWith(livenessVideo: mediaId),
      _ => current,
    };
    state = state.copyWith(mediaIds: updated);
  }

  /// Convenience for DocumentCaptureScreen: also advances [documentScanPhase]
  /// based on whether the selected ID type requires both sides.
  void setDocumentMediaId(String mediaId, {required String side}) {
    if (side == 'front') {
      final idType = state.selectedIdType;
      final config = getIdTypeConfig(_config.country, idType!);
      final needsBack = config?.scanSides == ScanSides.frontAndBack;
      state = state.copyWith(
        mediaIds: state.mediaIds.copyWith(documentFront: mediaId),
        documentScanPhase: needsBack ? 'back' : 'complete',
      );
    } else if (side == 'back') {
      state = state.copyWith(
        mediaIds: state.mediaIds.copyWith(documentBack: mediaId),
        documentScanPhase: 'complete',
      );
    }
  }

  void setUserData(UserData userData) {
    state = state.copyWith(userData: userData);
  }

  void clearError() {
    state = state.clearError();
  }

  // ── Async submission ───────────────────────────────────────────────────────
  //
  // Sends the verify request and returns immediately when the server responds
  // with 202 + { verificationId, status: 'pending' }. The actual verification
  // (OCR, YouVerify, facial comparison) runs asynchronously on the server and
  // the result arrives via webhook to the org's backend.
  //
  // Throws [KYCApiException] for network/auth/credit errors so the caller
  // (SubmittedScreen) can surface them via onError.

  Future<KYCSubmissionResult> submitAsync({
    void Function(int attempt, int total)? onRetry,
  }) async {
    final idType = state.selectedIdType;
    if (idType == null) {
      throw const KYCApiException(
        statusCode: 0,
        error: 'invalid_state',
        message: 'No ID type selected',
      );
    }

    final idTypeConfig = getIdTypeConfig(_config.country, idType);
    if (idTypeConfig == null) {
      throw const KYCApiException(
        statusCode: 0,
        error: 'invalid_state',
        message: 'Unsupported ID type for the selected country',
      );
    }

    // Number-only IDs require a typed-in idNumber and must pass format validation.
    String? idNumber = state.idNumber;
    if (!idTypeConfig.requiresDocumentCapture) {
      if (idNumber == null || idNumber.isEmpty) {
        throw const KYCApiException(
          statusCode: 0,
          error: 'invalid_state',
          message: 'No ID number provided',
        );
      }
      final validation = validateIdNumber(idNumber, _config.country, idType);
      if (!validation.isValid) {
        throw KYCApiException(
          statusCode: 0,
          error: 'invalid_state',
          message: validation.errorMessage ?? 'Invalid ID number',
        );
      }
    } else {
      // For document-required IDs, the server extracts the number via OCR.
      idNumber = null;
    }

    state = state.copyWith(isLoading: true);

    final requestId = _uuid.v4();
    final userIdRaw = _config.metadata?['userId'];
    final userId = userIdRaw is String ? userIdRaw : userIdRaw?.toString();

    final extraMeta = _config.metadata
        ?.map((k, v) => MapEntry(k, v.toString()))
      ?..remove('userId')
      ..remove('requestId');

    // Collect rich device metadata (best-effort — never blocks submission).
    Map<String, dynamic>? deviceMetadata;
    try {
      deviceMetadata = await DeviceMetadataService.instance.collect();
    } catch (_) {
      deviceMetadata = null;
    }

    final mediaIds = state.mediaIds;
    final request = VerifyRequest(
      country: _config.country.name,
      idType: idTypeConfig.key,
      idNumber: idNumber,
      userData: state.userData != null
          ? VerifyUserData(
              firstName: state.userData!.firstName,
              lastName: state.userData!.lastName,
              dateOfBirth: state.userData!.dateOfBirth,
            )
          : null,
      mediaIds: mediaIds.hasAny
          ? VerifyMediaIds(
              documentFront: mediaIds.documentFront,
              documentBack: mediaIds.documentBack,
              selfie: mediaIds.selfie,
              documentFrontVideo: mediaIds.documentFrontVideo,
              documentBackVideo: mediaIds.documentBackVideo,
              livenessVideo: mediaIds.livenessVideo,
            )
          : null,
      metadata: VerifyMetadata(
        requestId: requestId,
        userId: userId,
        extra: extraMeta,
        device: deviceMetadata,
      ),
    );

    try {
      // Retry the submission on transient failures (network / timeout / 5xx);
      // terminal errors (401/402/403/validation) surface immediately.
      final response = await withRetry(() => api.verify(request), onRetry: onRetry);
      final result = KYCSubmissionResult(
        verificationId: response.verificationId,
        status: response.status,
      );
      state = state.copyWith(isLoading: false, submissionResult: result);
      return result;
    } on KYCApiException {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void reset() {
    state = const KYCState();
  }
}
