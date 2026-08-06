import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../services/api_service.dart';
import '../services/device_metadata_service.dart';
import '../services/fingerprint_service.dart';
import '../services/nfc_reader.dart';
import '../services/mrz_parser.dart';
import '../services/retry.dart';
import '../services/validators.dart';
import '../utils/resolve_url.dart';
import 'kyc_state.dart';
import 'step_order.dart';

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

/// Server config preloaded by the launcher when a workflow was resolved before
/// mount (its `idTypes`/`branding` come from the workflow resolution, so the
/// flow skips the `/api/kyc/config` fetch). Null (the default) means "fetch
/// `/config` on mount". Overridden with a value in the ProviderScope by the
/// workflow gate. A plain provider (not codegen) so no build_runner step is
/// needed to add it.
final preloadedServerConfigProvider =
    Provider<ServerSdkConfig?>((ref) => null);

// ─── Shared UUID generator ────────────────────────────────────────────────────

const _uuid = Uuid();

// ─── KYC flow notifier ────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
/// Merge the consumer's `userData` prop with anything typed in-flow.
///
/// The prop wins per field; typed values fill what it omits. Empty strings count as
/// ABSENT — submitting `firstName: ''` would ask the server to compare the document
/// against nothing, and null is the honest representation of "not provided".
/// Returns null when there is nothing to compare at all, which is what leaves
/// `dataMatch` null server-side.
///
/// WHY THIS EXISTS: the submit used to read `state.userData` alone. `setUserData` is
/// called from the ID-input screen and nowhere else, and that screen appears only for
/// number-only ids (BVN/NIN) — so for every DOCUMENT id (passport, PVC, driver's
/// licence, Ghana Card) the integrator's `userData` was silently dropped and the name
/// comparison could never run. Mirrors the React SDK's precedence.
VerifyUserData? resolveVerifyUserData(UserData? fromProp, UserData? fromState) {
  String? pick(String? prop, String? typed) {
    final value = (prop != null && prop.isNotEmpty) ? prop : typed;
    return (value != null && value.isNotEmpty) ? value : null;
  }

  final firstName = pick(fromProp?.firstName, fromState?.firstName);
  final lastName = pick(fromProp?.lastName, fromState?.lastName);
  final dateOfBirth = pick(fromProp?.dateOfBirth, fromState?.dateOfBirth);

  if (firstName == null && lastName == null && dateOfBirth == null) return null;
  return VerifyUserData(
    firstName: firstName,
    lastName: lastName,
    dateOfBirth: dateOfBirth,
  );
}

class KYCNotifier extends _$KYCNotifier {
  @override
  KYCState build() {
    // When the launcher resolved a workflow before mount, its idTypes/branding
    // are already known — use them directly and skip the /config fetch.
    final preloaded = ref.read(preloadedServerConfigProvider);
    if (preloaded != null) {
      return KYCState(serverConfig: preloaded);
    }
    // Otherwise kick off the /api/kyc/config fetch asynchronously. The state
    // starts in ServerConfigStatus.loading and the screens render placeholders
    // until this resolves. Errors fall through to status: error and the SDK
    // falls back to the consumer's `idTypes` prop (server still 403s anything
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

  // ── Step navigation ────────────────────────────────────────────────────────
  //
  // Navigation is driven by `buildStepOrder` (step_order.dart) — the single
  // ordered list for the current config + state. next/previous move within it,
  // so inserting an optional step (country-select, proof-of-address, …) needs
  // no changes here. The list is recomputed each time, so a step that depends
  // on later state (document-capture vs id-input, per-ID liveness) resolves
  // once that state is known.

  /// Advances to the next step in the computed order (no-op at the terminal
  /// step or if the current step isn't in the order).
  void nextStep() {
    final order = buildStepOrder(_config, state);
    final idx = order.indexOf(state.currentStep);
    if (idx >= 0 && idx + 1 < order.length) {
      state = state.copyWith(currentStep: order[idx + 1]);
    }
  }

  /// Goes back one step in the computed order (no-op at the first step).
  void previousStep() {
    final order = buildStepOrder(_config, state);
    final idx = order.indexOf(state.currentStep);
    if (idx > 0) {
      state = state.copyWith(currentStep: order[idx - 1]);
    }
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  /// Picks the country in a multi-region flow. Clears the selected ID (the new
  /// country has its own ID list) and any captured document phase.
  void setCountry(String country) {
    if (country == state.selectedCountry) return;
    state = state.copyWith(
      selectedCountry: country,
      clearSelectedIdType: true,
      documentScanPhase: 'front',
      docReviewPhase: 'camera',
    );
  }

  void setIdType(IdTypeConfig idType) {
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

  /// Raised while a full-bleed camera is on screen so the sheet drops its
  /// chrome; lowered the moment it leaves.
  void setImmersiveCapture(bool immersive) {
    if (state.immersiveCapture == immersive) return;
    state = state.copyWith(immersiveCapture: immersive);
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
      final needsBack =
          state.selectedIdType?.scanSides == ScanSides.frontAndBack;
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

  /// Stores the questionnaire answers (money fields include their `_currency`
  /// companion key). Submitted under `questionnaire` on /verify.
  void setQuestionnaireAnswers(Map<String, dynamic> answers) {
    state = state.copyWith(questionnaireAnswers: answers);
  }

  /// Stores a contact-verification proof (email or phone OTP token +
  /// destination). Submitted under `contact` on /verify.
  void setContactProof(String channel, String token, String destination) {
    if (channel == 'email') {
      state = state.copyWith(emailToken: token, emailAddress: destination);
    } else {
      state = state.copyWith(phoneToken: token, phoneNumber: destination);
    }
  }

  /// Stores the liveness step's capture-integrity claim (mode + flash result).
  void setLivenessIntegrity(Map<String, dynamic> liveness) {
    state = state.copyWith(integrity: {...state.integrity, 'liveness': liveness});
  }

  /// Stores the eMRTD chip data read in the NFC step. Submitted under `nfc`.
  void setNfcChipData(NfcChipData data) {
    state = state.copyWith(nfcChipData: data);
  }

  /// Records the MRZ read off the captured document photo (the BAC key), so the
  /// chip step doesn't need its own camera pass.
  void setMrzScan(MrzScan scan) {
    state = state.copyWith(mrzScan: scan);
  }

  /// Stores the KYB business-details step inputs. Submitted under `business`.
  void setBusinessDetails({
    required String country,
    required String product,
    required String registrationNumber,
    String? registrationName,
  }) {
    state = state.copyWith(
      businessCountry: country,
      businessProduct: product,
      registrationNumber: registrationNumber,
      registrationName: registrationName,
    );
  }

  /// Stores the uploaded proof-of-address document (its mediaId + type key).
  void setProofOfAddress(String mediaId, String typeKey) {
    state = state.copyWith(
      mediaIds: state.mediaIds.copyWith(proofOfAddress: mediaId),
      poaDocumentType: typeKey,
    );
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

  // Consumer `metadata` (stringified, requestId stripped — the SDK owns that).
  Map<String, String>? _extraMetadata() => _config.metadata
      ?.map((k, v) => MapEntry(k, v.toString()))
    ?..remove('requestId');

  // Rich device metadata (+ fingerprint when Device Intelligence is on).
  // Best-effort — never blocks submission.
  Future<Map<String, dynamic>?> _collectDeviceMetadata() async {
    try {
      final collected = await DeviceMetadataService.instance.collect();
      // The integrity claim rides here regardless of Device Intelligence: it
      // describes the CAPTURE (which liveness method ran, and its outcome), not
      // the device, and the server's liveness re-scoring needs the claimed
      // flash sequence to have anything to verify the recording against.
      final integrity = state.integrity;
      return {
        ...collected,
        if (integrity.isNotEmpty) 'integrity': integrity,
        if (_config.deviceIntelligence)
          'fingerprint': await FingerprintService.instance.collect(),
      };
    } catch (_) {
      return null;
    }
  }

  // Business (KYB) submission — a registry lookup, no captured media. Requires a
  // published KYB workflow (the server 404s a business body without one).
  Future<KYCSubmissionResult> _submitBusiness({
    void Function(int attempt, int total)? onRetry,
  }) async {
    final biz = _config.business;
    final country = state.businessCountry ?? biz?.country ?? effectiveCountry(_config, state);
    final product =
        state.businessProduct ?? (biz?.offeredProducts.first ?? 'business');
    final regNumber = state.registrationNumber?.trim();
    if (regNumber == null || regNumber.isEmpty) {
      throw const KYCApiException(
        statusCode: 0,
        error: 'invalid_state',
        message: 'No registration number provided',
      );
    }

    state = state.copyWith(isLoading: true);
    final requestId = _uuid.v4();
    final request = VerifyRequest(
      country: country,
      idType: product, // the product key rides idType for KYB
      workflowId: _config.workflowId,
      userId: _config.userId,
      subjectType: 'business',
      business: VerifyBusiness(
        registrationNumber: regNumber,
        registrationName: state.registrationName,
        product: product,
      ),
      questionnaire: state.questionnaireAnswers.isNotEmpty
          ? state.questionnaireAnswers
          : null,
      deviceIntelligence: _config.deviceIntelligence,
      metadata: VerifyMetadata(
        requestId: requestId,
        extra: _extraMetadata(),
        device: await _collectDeviceMetadata(),
      ),
    );

    try {
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

  Future<KYCSubmissionResult> submitAsync({
    void Function(int attempt, int total)? onRetry,
  }) async {
    if (_config.subjectType == 'business') {
      return _submitBusiness(onRetry: onRetry);
    }

    final idTypeConfig = state.selectedIdType;
    if (idTypeConfig == null) {
      throw const KYCApiException(
        statusCode: 0,
        error: 'invalid_state',
        message: 'No ID type selected',
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
      final validation = validateIdNumber(
          idNumber, effectiveCountry(_config, state), idTypeConfig.key);
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
    // The org's user reference is the typed top-level `userId` field (becomes
    // Entity.externalUserId at the KYC seam). `metadata` is free-form passthrough.
    final userId = _config.userId;
    final extraMeta = _extraMetadata();
    final deviceMetadata = await _collectDeviceMetadata();

    final mediaIds = state.mediaIds;
    final request = VerifyRequest(
      country: effectiveCountry(_config, state),
      idType: idTypeConfig.key,
      idNumber: idNumber,
      workflowId: _config.workflowId,
      // Only sent for prop mounts; a resolved workflow's mode wins server-side.
      livenessMode: _config.workflowId == null ? _config.livenessMode : null,
      userId: userId,
      // Consumer prop FIRST, typed values fill the gaps — mirroring the React SDK.
      //
      // Reading only `state.userData` silently dropped the integrator's `userData`
      // for every DOCUMENT id: `setUserData` is called from the ID-input screen
      // alone, and that screen exists only for number-only ids (BVN/NIN). So a
      // passport or PVC submitted `userData: null` no matter what the app passed,
      // the server had nothing to compare the document against, and `dataMatch`
      // came back null with no indication why.
      userData: resolveVerifyUserData(_config.userData, state.userData),
      mediaIds: mediaIds.hasAny
          ? VerifyMediaIds(
              documentFront: mediaIds.documentFront,
              documentBack: mediaIds.documentBack,
              selfie: mediaIds.selfie,
              documentFrontVideo: mediaIds.documentFrontVideo,
              documentBackVideo: mediaIds.documentBackVideo,
              livenessVideo: mediaIds.livenessVideo,
              proofOfAddress: mediaIds.proofOfAddress,
            )
          : null,
      questionnaire: state.questionnaireAnswers.isNotEmpty
          ? state.questionnaireAnswers
          : null,
      proofOfAddressType:
          mediaIds.proofOfAddress != null ? state.poaDocumentType : null,
      deviceIntelligence: _config.deviceIntelligence,
      contact: (state.emailToken != null || state.phoneToken != null)
          ? VerifyContact(
              emailToken: state.emailToken,
              phoneToken: state.phoneToken,
            )
          : null,
      // Validate-and-drop: only send chip data for a chip-capable selected ID
      // (mirrors the server, which drops the block for non-chip IDs).
      nfc: (state.nfcChipData != null && idTypeConfig.supportsNfc)
          ? VerifyNfc(
              dg1: state.nfcChipData!.dg1Base64,
              sod: state.nfcChipData!.sodBase64,
              dg2: state.nfcChipData!.dg2Base64,
              chipAuth: state.nfcChipData!.chipAuth,
              paceOutcome: state.nfcChipData!.paceOutcome,
              paceDetail: state.nfcChipData!.paceDetail,
            )
          : null,
      metadata: VerifyMetadata(
        requestId: requestId,
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
