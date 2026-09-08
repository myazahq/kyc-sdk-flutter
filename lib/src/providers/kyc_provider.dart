import 'dart:convert';
import '../config/scope.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../config/address_collection.dart';
import '../config/business.dart';
import '../config/business_application.dart';
import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/selfie_upload_wait.dart';
import 'session_progress.dart';
import 'session_restore.dart';
import '../config/key_people_prefill.dart';
import '../services/api_service.dart';
import '../services/device_metadata_service.dart';
import '../services/fingerprint_service.dart';
import '../services/nfc_reader.dart';
import '../services/mrz_parser.dart';
import '../services/retry.dart';
import '../services/validators.dart';
import '../utils/address_current_location.dart';
import '../utils/resolve_url.dart';
import '../utils/step_log.dart';
import 'kyc_state.dart';
import 'address_step_order.dart';
import 'step_order.dart';
import '../config/multi_id.dart';

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

/// The API client, as a provider so tests can stub the network. Null (the
/// default) means "build one from the mounted config"; a plain provider (not
/// codegen) so no build_runner step is needed to add it.
final kycApiServiceProvider = Provider<KYCApiService?>((ref) => null);

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
    // Step journey log — a fresh provider lifecycle is a fresh session. The
    // self-listener catches EVERY currentStep write, whatever method made it;
    // StepLog.record collapses consecutive duplicates. Rides the submission
    // as metadata.device.stepLog for the dashboard timeline.
    StepLog.reset();
    // The step the flow opens on: consent, or the first real step when the
    // workflow switched the consent screen off (`consentStep: false`). Read
    // WITH the preloaded server config when a workflow was resolved before
    // mount: which steps exist depends on it (see openingStep).
    final preloaded = ref.read(preloadedServerConfigProvider);
    final opening = openingStep(_config, serverConfig: preloaded);
    StepLog.record(opening);
    // A second run of the SDK in one app process is a new attempt, possibly by
    // a different person somewhere else, so the shared location fix starts
    // empty rather than answering with the last applicant's coordinates.
    resetCurrentFix();
    listenSelf((previous, next) {
      if (previous?.currentStep != next.currentStep) {
        StepLog.record(
          next.currentStep,
          slot: next.multiIdSlots.isNotEmpty ? next.multiIdSlots.length + 1 : null,
          idType: next.selectedIdType?.key,
        );
      }
      _scheduleProgressSave(next);
    });

    // The attempt session: minted at launch (a fresh provider lifecycle IS a
    // fresh attempt). Best-effort by contract — sessions power resumability,
    // the dashboard's live attempt view, and the registry check at selection;
    // verifying is never conditional on one existing. Called directly rather
    // than through a scheduled Future: a zero-duration timer reads as pending
    // work to widget tests, and there is nothing here that needs deferring.
    unawaited(_startAttemptSession());
    // A debounce timer must not outlive its provider — in production that is a
    // leak, in a widget test it is a teardown failure.
    ref.onDispose(() => _progressTimer?.cancel());

    // When the launcher resolved a workflow before mount, its idTypes/branding
    // are already known — use them directly and skip the /config fetch.
    if (preloaded != null) {
      return KYCState(currentStep: opening, serverConfig: preloaded);
    }
    // Otherwise kick off the /api/kyc/config fetch asynchronously. The state
    // starts in ServerConfigStatus.loading and the screens render placeholders
    // until this resolves. Errors fall through to status: error and the SDK
    // falls back to the consumer's `idTypes` prop (server still 403s anything
    // actually disabled, so this is at worst as restrictive as the server).
    Future.microtask(_loadServerConfig);
    return KYCState(currentStep: opening);
  }

  Future<void> _loadServerConfig() async {
    try {
      final response = await api.config();
      final ready = ServerSdkConfig(
        status: ServerConfigStatus.ready,
        idTypes: response.idTypes,
        environment: response.environment,
        branding: response.branding,
        geoCountry: response.geoCountry,
        addressSearch: response.addressSearch,
        addressSearchMode: response.addressSearchMode,
        mapsFrameUrl: response.mapsFrameUrl,
      );
      // The facts that just landed can add a step AHEAD of the one the flow
      // opened on (the address search step, on a consent-less address flow).
      // Someone still standing on the placeholder's opening step, having
      // done nothing, is moved to the real one; anyone who has moved is left
      // alone. Same nudge as the RN store's loadServerConfig.
      final before = openingStep(_config, serverConfig: state.serverConfig);
      final after = openingStep(_config, serverConfig: ready);
      state = state.copyWith(
        serverConfig: ready,
        currentStep: state.currentStep == before && after != before ? after : null,
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

  KYCApiService get api =>
      ref.read(kycApiServiceProvider) ??
      KYCApiService(
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
  /// The steps that make up ONE ID's evidence. Leaving this set is what ends a
  /// multi-ID check — the leg has several exits depending on the ID.
  static const Set<KYCStep> _idEvidenceSteps = {
    KYCStep.idInput,
    KYCStep.documentCapture,
    KYCStep.nfc,
  };

  void nextStep() {
    final order = buildStepOrder(_config, state);
    final idx = order.indexOf(state.currentStep);
    if (idx < 0 || idx + 1 >= order.length) return;
    final next = order[idx + 1];

    // Multi-ID: the run walks the capture leg once PER ID. Intercepted at this
    // one seam rather than in each screen because it is one rule — "the
    // applicant finished this check" — and the leg has several exits (a
    // number-only ID leaves from idInput, a document ID from documentCapture
    // or the chip read after it).
    final plan = multiIdPlan();
    if (plan != null &&
        _idEvidenceSteps.contains(state.currentStep) &&
        !_idEvidenceSteps.contains(next)) {
      commitMultiIdSlot(plan.last ? next : KYCStep.idType);
      return;
    }
    state = state.copyWith(currentStep: next);
  }

  /// The chip payload as the wire wants it. One builder, so a check's chip and
  /// a single-ID run's are byte-identical to the server.
  static VerifyNfc _nfcPayload(NfcChipData chip) => VerifyNfc(
        dg1: chip.dg1Base64,
        sod: chip.sodBase64,
        dg2: chip.dg2Base64,
        dg7: chip.dg7Base64,
        dg11: chip.dg11Base64,
        dg12: chip.dg12Base64,
        dg15: chip.dg15Base64,
        aaSignature: chip.aaSignatureBase64,
        aaChallengeId: chip.aaChallengeId,
        chipAuth: chip.chipAuth,
        paceOutcome: chip.paceOutcome,
        paceDetail: chip.paceDetail,
      );

  /// The active multi-ID plan for the current state, or null on an ordinary run.
  ///
  /// Mirrors the web SDK's `multiIdPlan`: the server validates the pick
  /// sequence this produces, so the options offered here and the options the
  /// server accepts have to be the same set.
  MultiIdPlan? multiIdPlan() {
    final cfg = _config.multiId;
    if (cfg == null || _config.subjectType == 'business') return null;

    final country = effectiveCountry(_config, state);
    final entry = (_config.countries ?? const <WorkflowCountryOption>[])
        .cast<WorkflowCountryOption?>()
        .firstWhere((c) => c?.country == country, orElse: () => null);

    // The country's pinned list, else everything the server granted there.
    final offered = (entry?.idTypes != null && entry!.idTypes!.isNotEmpty)
        ? entry.idTypes!
        : (_config.idTypes != null && _config.idTypes!.isNotEmpty)
            ? _config.idTypes!
            : state.serverConfig.idTypes
                .where((row) => row.country == country)
                .map((row) => row.idType)
                .toList(growable: false);

    final options = multiIdSlotOptions(cfg.count, entry?.multiIdSlots, offered);
    final picked =
        state.multiIdSlots.map((s) => s.idType).toList(growable: false);
    final index = state.multiIdSlotIndex.clamp(0, cfg.count);
    return MultiIdPlan(
      count: cfg.count,
      minPassed: cfg.minPassed,
      index: index,
      last: index >= cfg.count - 1,
      picked: picked,
      safeOptions:
          index < cfg.count ? multiIdSafeOptions(options, index, picked) : const [],
    );
  }

  /// Commits the current check's evidence and moves on.
  ///
  /// The SELFIE and its video are run-level and deliberately untouched: one
  /// selfie covers every ID in the run.
  void commitMultiIdSlot(KYCStep nextStep) {
    final idType = state.selectedIdType;
    if (idType == null) return;
    final media = state.mediaIds;
    final slot = MultiIdSlot(
      idType: idType.key,
      idNumber: state.idNumber,
      documentFront: media.documentFront,
      documentBack: media.documentBack,
      documentFrontVideo: media.documentFrontVideo,
      documentBackVideo: media.documentBackVideo,
      chipData: state.nfcChipData,
    );
    state = state.copyWith(
      multiIdSlots: [...state.multiIdSlots, slot],
      multiIdSlotIndex: state.multiIdSlotIndex + 1,
      clearSelectedIdType: true,
      // Rebuilt rather than copyWith'd: copyWith cannot CLEAR a document id,
      // and carrying the last check's document into the next one would file it
      // against the wrong ID. The selfie and its video are run-level and kept.
      // Rebuilt rather than copyWith'd: copyWith cannot CLEAR an id, and
      // carrying this check's document or its recording into the next one
      // would file them against the wrong ID. The selfie and its liveness
      // video are run-level and kept.
      mediaIds: KYCMediaIds(
        selfie: media.selfie,
        livenessVideo: media.livenessVideo,
        proofOfAddress: media.proofOfAddress,
      ),
      documentScanPhase: 'front',
      docReviewPhase: 'camera',
      // The chip belongs to the check just committed; the next reads its own.
      clearNfcChipData: true,
      currentStep: nextStep,
    );
  }

  /// Steps BACK into the previous check, restoring what it captured.
  void uncommitMultiIdSlot() {
    if (state.multiIdSlots.isEmpty) return;
    final last = state.multiIdSlots.last;
    final row = state.serverConfig.idTypes
        .cast<SdkConfigIdType?>()
        .firstWhere((r) => r?.idType == last.idType, orElse: () => null);
    final def = resolveIdTypeDefinition(
      effectiveCountry(_config, state),
      last.idType,
      label: row?.label,
      requiresDocumentCapture: row?.requiresDocumentCapture,
      scanSides: row?.scanSides,
      supportsNfc: row?.supportsNfc,
    );
    state = state.copyWith(
      multiIdSlots:
          state.multiIdSlots.sublist(0, state.multiIdSlots.length - 1),
      multiIdSlotIndex: (state.multiIdSlots.length - 1).clamp(0, 3),
      selectedIdType: def,
      idNumber: last.idNumber,
      mediaIds: state.mediaIds.copyWith(
        documentFront: last.documentFront,
        documentBack: last.documentBack,
        documentFrontVideo: last.documentFrontVideo,
        documentBackVideo: last.documentBackVideo,
      ),
      nfcChipData: last.chipData,
      currentStep: def.requiresDocumentCapture
          ? KYCStep.documentCapture
          : KYCStep.idInput,
    );
  }

  /// Goes back one step in the computed order (no-op at the first step).
  void previousStep() {
    // Multi-ID: stepping back from the picker means re-doing the PREVIOUS
    // check, not leaving the flow. The check is uncommitted so its ID number
    // and captures come back — changing an earlier ID must not mean
    // re-photographing a document that is still perfectly good.
    if (state.currentStep == KYCStep.idType && state.multiIdSlots.isNotEmpty) {
      uncommitMultiIdSlot();
      return;
    }
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
      countryAutoPicked: false,
      clearSelectedIdType: true,
      documentScanPhase: 'front',
      docReviewPhase: 'camera',
    );
  }

  /// Declare a GUESSED country (the address scope's IP default, a geocode
  /// from the applicant's fix): the same reset as [setCountry], flagged so
  /// later evidence may correct it. Mirrors the web SDK's SET_COUNTRY_AUTO.
  void setCountryAuto(String country) {
    setCountry(country);
    if (!state.countryAutoPicked) {
      state = state.copyWith(countryAutoPicked: true);
    }
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

  /// Publish what the contact step is doing so the sheet header can caption it.
  /// Pass an empty [destination] while the user is still entering one.
  void setContactHeader({
    required String channel,
    String via = '',
    String destination = '',
  }) {
    if (state.contactChannel == channel &&
        state.contactVia == via &&
        state.contactDestination == destination) {
      return;
    }
    state = state.copyWith(
      contactChannel: channel,
      contactVia: via,
      contactDestination: destination,
    );
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

  /// The captured selfie's base64 preview, kept centrally so the liveness
  /// screen restores its review on return (its own state and the autoDispose
  /// liveness provider die with it on step change).
  void setSelfieImage(String selfieBase64) {
    state = state.copyWith(selfieImage: selfieBase64);
  }

  /// Retake: drop the selfie preview and its uploaded media ids in one set
  /// (the upload's record goes with them, see [setSelfieUpload]).
  void clearSelfie() {
    state = state.copyWith(
      clearSelfieImage: true,
      mediaIds: state.mediaIds.copyWith(clearSelfie: true),
    );
  }

  /// The selfie upload's progress report. The liveness screen writes it; the
  /// submitted screen waits on it when the review is hidden (the biometric
  /// scopes hand over before the upload lands). See
  /// config/selfie_upload_wait.dart.
  void setSelfieUpload(SelfieUploadState upload) {
    state = state.copyWith(selfieUpload: upload);
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
    // A fresh proof clears its channel's "server refused this" flag.
    final expired = [
      for (final c in state.expiredContact)
        if (c != channel) c,
    ];
    if (channel == 'email') {
      state = state.copyWith(
          emailToken: token, emailAddress: destination, expiredContact: expired);
    } else {
      state = state.copyWith(
          phoneToken: token, phoneNumber: destination, expiredContact: expired);
    }
  }

  /// The server refused these channels' proofs at submit (single-use tokens
  /// expire ~30 minutes after the OTP check, and session restore can resurrect
  /// a dead one). Drop the tokens, keep the destinations, and flag the
  /// channels so their steps explain, re-verify, and resubmit.
  void clearContactProofs(List<String> channels) {
    state = state.copyWith(
      clearEmailToken: channels.contains('email'),
      clearPhoneToken: channels.contains('phone'),
      expiredContact: channels,
    );
  }

  /// Jump to a specific step (used by submit recovery to return the applicant
  /// to a contact step, and by that step to return to `submitted`).
  void goToStep(KYCStep step) {
    if (state.currentStep != step) state = state.copyWith(currentStep: step);
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

  /// The business fields whose change means a DIFFERENT company is being
  /// asked about — which invalidates the register's answer.
  static const _businessIdentityKeys = {
    'registrationNumber',
    'country',
    'product',
  };

  /// One business field, in the canonical-key vocabulary shared with
  /// `registerPrefillPatch` and `businessFieldValues`.
  KYCState _withBusinessValue(KYCState s, String key, String value) =>
      switch (key) {
        'country' => s.copyWith(businessCountry: value),
        'product' => s.copyWith(businessProduct: value),
        'registrationNumber' => s.copyWith(registrationNumber: value),
        'registrationName' => s.copyWith(registrationName: value),
        'subdivisionCode' => s.copyWith(businessSubdivisionCode: value),
        'sandboxOutcome' => s.copyWith(businessSandboxOutcome: value),
        'contactEmail' => s.copyWith(businessContactEmail: value),
        'address' => s.copyWith(businessAddress: value),
        'email' => s.copyWith(businessEmail: value),
        'phone' => s.copyWith(businessPhone: value),
        'website' => s.copyWith(businessWebsite: value),
        'dateOfIncorporation' =>
          s.copyWith(businessDateOfIncorporation: value),
        'taxId' => s.copyWith(businessTaxId: value),
        'vatNumber' => s.copyWith(businessVatNumber: value),
        'companyType' => s.copyWith(businessCompanyType: value),
        'natureOfBusiness' => s.copyWith(businessNatureOfBusiness: value),
        _ => s,
      };

  /// Stores one KYB business-details field. Submitted under `business`.
  ///
  /// Any change to WHICH company this is about (number/country/product)
  /// invalidates the answer we hold, so the check never describes one business
  /// while the field names another. Everything the previous register told us
  /// about the old company goes with it — only what the REGISTER wrote: an
  /// applicant who typed their own address meant it. Clearing it also unblocks
  /// the next lookup, whose prefill only ever writes into an empty field, so
  /// leftovers were not merely stale, they were suppressing the real answer.
  /// Mirrors the RN store's setBusinessField.
  void setBusinessField(String key, String value) {
    final identityChanged = _businessIdentityKeys.contains(key);
    var next = state;
    if (identityChanged) {
      for (final prefilledKey in state.businessCheck.prefilled) {
        if (prefilledKey != key) {
          next = _withBusinessValue(next, prefilledKey, '');
        }
      }
    }
    next = _withBusinessValue(next, key, value);
    if (identityChanged) {
      next = next.copyWith(businessCheck: const BusinessCheckState());
    }
    state = next;
  }

  /// Writes the register's answers into empty fields + records which ones it
  /// filled, in one set — so a company change can clear exactly those.
  void applyBusinessPrefill(Map<String, String> patch, List<String> prefilled) {
    var next = state;
    patch.forEach((key, value) {
      next = _withBusinessValue(next, key, value);
    });
    state = next.copyWith(
      businessCheck: next.businessCheck.copyWith(prefilled: prefilled),
    );
  }

  /// Replaces the applicant-declared directors/owners (business-key-people).
  void setKeyPeople(List<KeyPersonEntry> people) {
    state = state.copyWith(keyPeople: people);
  }

  /// The applicant attests that no natural person qualifies as a UBO.
  void setUboUnidentifiable(bool value) {
    state = state.copyWith(uboUnidentifiable: value);
  }

  /// Records one uploaded supporting document, replacing any prior upload for
  /// the same slot (re-picking a file must not submit both).
  void setBusinessDocument(BusinessDocumentUpload upload) {
    state = state.copyWith(
      businessDocuments: [
        ...state.businessDocuments.where((d) => d.type != upload.type),
        upload,
      ],
    );
  }

  /// Drops the upload for one document slot.
  void removeBusinessDocument(String type) {
    state = state.copyWith(
      businessDocuments:
          state.businessDocuments.where((d) => d.type != type).toList(),
    );
  }

  /// Stores the applicant's declared role + optional full name.
  /// [keyPersonIndex] = the applicant picked THEMSELVES from the entered key
  /// people (index into state.keyPeople); null = they're someone else.
  void setApplicant({required ApplicantRole role, String? name, int? keyPersonIndex}) {
    state = state.copyWith(
      applicantRole: role,
      applicantName: name,
      applicantKeyPersonIndex: keyPersonIndex,
      clearApplicantKeyPersonIndex: keyPersonIndex == null,
    );
  }

  /// Stores the uploaded proof-of-address document (its mediaId + type key).
  /// Drops the uploaded proof-of-address document, returning the step to its
  /// empty state (the user tapped the row's X, or switched document kind —
  /// keeping the file would mislabel it).
  void clearProofOfAddress() {
    state = state.copyWith(
      mediaIds: state.mediaIds.copyWith(clearProofOfAddress: true),
      clearPoaDocumentType: true,
    );
  }

  void setProofOfAddress(String mediaId, String typeKey) {
    state = state.copyWith(
      mediaIds: state.mediaIds.copyWith(proofOfAddress: mediaId),
      poaDocumentType: typeKey,
    );
  }

  /// Stores the smart address the address-collection step gathered (the pin,
  /// directions, and — when attestPresence took one — the device fix).
  /// Dev/sandbox only (the review step's Test-result tabs).
  void setAddressSandboxOutcome(String? outcome) {
    state = state.copyWith(addressSandboxOutcome: outcome);
  }

  void setAddress(AddressState address) {
    state = state.copyWith(address: address);
  }

  /// Records the uploaded door photo's mediaId.
  void setAddressPhoto(String mediaId) {
    state = state.copyWith(
      mediaIds: state.mediaIds.copyWith(addressPhoto: mediaId),
    );
  }

  /// The local path of the uploaded entrance photo, so the review step can
  /// show it. A display artefact — it never reaches the server or a snapshot.
  void setAddressPhotoPreview(String? path) {
    state = state.copyWith(
      addressPhotoPreview: path,
      clearAddressPhotoPreview: path == null,
    );
  }

  /// The presence primer was acknowledged, so it is not shown again this
  /// session.
  void markAddressIntroSeen() {
    state = state.copyWith(addressIntroSeen: true);
  }

  /// The entrance step is (or stops) showing the Street View framer: the
  /// sheet header reads the mode off this.
  void setAddressEntranceFraming(bool framing) {
    if (state.addressEntranceFraming == framing) return;
    state = state.copyWith(addressEntranceFraming: framing);
  }

  /// Starts the address over: the pin, the uploaded photo and its preview go
  /// together, because a photo of an entrance is about the pin it was taken
  /// for and keeping one without the other says something untrue.
  void clearAddress() {
    state = state.copyWith(
      clearAddress: true,
      clearAddressPhotoPreview: true,
      mediaIds: state.mediaIds.copyWith(clearAddressPhoto: true),
    );
  }

  /// Drops the door photo (the user tapped the row's X).
  void clearAddressPhoto() {
    state = state.copyWith(
      mediaIds: state.mediaIds.copyWith(clearAddressPhoto: true),
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
      // Step journey recorded during the session — powers the dashboard's
      // verification timeline. See utils/step_log.
      // Each part is collected on its OWN so one failure costs that part alone.
      // A single catch around the lot meant a TypeError in the step-log
      // snapshot silently discarded the whole device block — no fingerprint, no
      // SDK identity, no journey — and the verification looked like it came
      // from an unknown device. Diagnostics must degrade piecewise; losing all
      // of them together is indistinguishable from an SDK that sends none.
      Map<String, dynamic>? stepLog;
      try {
        stepLog = StepLog.snapshot();
      } catch (_) {
        stepLog = null;
      }

      Map<String, dynamic>? fingerprint;
      if (_config.deviceIntelligence) {
        try {
          fingerprint = await FingerprintService.instance.collect();
        } catch (_) {
          fingerprint = null;
        }
      }

      return {
        ...collected,
        if (integrity.isNotEmpty) 'integrity': integrity,
        if (stepLog != null) 'stepLog': stepLog,
        if (fingerprint != null) 'fingerprint': fingerprint,
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

    // Application extras ride the business block ONLY when the workflow
    // configures them — the server ignores unconfigured fields anyway, but
    // sending them would misrepresent what the applicant was actually asked.
    final biz2 = biz;
    final documents = hasBusinessDocumentsStep(biz2)
        ? state.businessDocuments.map((d) => d.toJson()).toList(growable: false)
        : null;
    final keyPeople =
        hasKeyPeopleCollection(biz2)
            ? keyPeoplePayload(state.keyPeople,
                applicantIndex: state.applicantKeyPersonIndex)
            : null;
    final applicant =
        hasApplicantVerification(biz2) && state.applicantRole != null
            ? {
                'role': state.applicantRole!.key,
                if ((state.applicantName ?? '').trim().isNotEmpty)
                  'name': state.applicantName!.trim(),
              }
            : null;

    state = state.copyWith(isLoading: true);
    final requestId = _uuid.v4();
    final request = VerifyRequest(
      sessionId: state.sessionId,
      country: country,
      idType: product, // the product key rides idType for KYB
      workflowId: _config.workflowId,
      userId: _config.userId,
      subjectType: 'business',
      business: VerifyBusiness(
        registrationNumber: regNumber,
        registrationName: state.registrationName,
        product: product,
        contactEmail: state.businessContactEmail,
        address: state.businessAddress,
        email: state.businessEmail,
        phone: state.businessPhone,
        website: state.businessWebsite,
        // The five registry facts the applicant STATES, sent only when filled
        // (VerifyBusiness.toJson drops empties). Mirrors the RN submission.
        dateOfIncorporation: state.businessDateOfIncorporation,
        taxId: state.businessTaxId,
        vatNumber: state.businessVatNumber,
        companyType: state.businessCompanyType,
        natureOfBusiness: state.businessNatureOfBusiness,
        documents: documents,
        keyPeople: keyPeople,
        uboUnidentifiable: state.uboUnidentifiable,
        applicant: applicant,
      ),
      // The premises pin, when the address step gathered one (a KYB flow's pin
      // is the BUSINESS PREMISES, checked against the registry address).
      address: state.address != null
          ? addressPayload(state.address!, config: _config.addressCollection)
          : null,
      questionnaire: state.questionnaireAnswers.isNotEmpty
          ? state.questionnaireAnswers
          : null,
      deviceIntelligence: _config.deviceIntelligence,
      contact: (state.emailToken != null || state.phoneToken != null)
          ? VerifyContact(
              emailToken: state.emailToken,
              phoneToken: state.phoneToken,
            )
          : null,
      metadata: VerifyMetadata(
        requestId: requestId,
        extra: {
          ...?_extraMetadata(),
          // The dev/sandbox test-result pin. Ignored by production, so it is
          // safe to send whenever it is set.
          if ((state.businessSandboxOutcome ?? '').isNotEmpty)
            'sandboxOutcome': state.businessSandboxOutcome!,
        },
        device: await _collectDeviceMetadata(),
      ),
    );

    try {
      final response = await withRetry(() => api.verify(request), onRetry: onRetry);
      final result = KYCSubmissionResult(
        verificationId: response.verificationId,
        status: response.status,
      );
      state = state.copyWith(
        isLoading: false,
        submissionResult: result,
        // The success screen hands these out — per-person verification links
        // for full-KYC key people (a retried requestId returns them again).
        keyPeopleInvites: response.keyPeopleInvites,
      );

      // The applicant's own KYC is FIRE-AND-FORGET: the submitted screen shows
      // after the BUSINESS submit, and a failure here only warns — the org can
      // re-invite the applicant from the dashboard. Awaiting it would make a
      // flaky second request fail an already-accepted business submission.
      final applicantKeyPersonId = response.applicantKeyPersonId;
      if (applicantKeyPersonId != null && _applicantMediaCaptured) {
        unawaited(
          // The LEG's effective country (their country-select choice, or the
          // overlaid applicant workflow's default) — never forced to the
          // business registry country. A GH-passport applicant on an
          // NG-registered business must submit country=GH.
          _submitApplicantVerification(
                  effectiveCountry(_config, state), applicantKeyPersonId)
              .catchError((Object err) {
            if (kDebugMode) {
              debugPrint(
                '[MyazaKYC] Applicant identity submission failed — the '
                'organization can re-invite the applicant from the dashboard: $err',
              );
            }
          }),
        );
      }

      return result;
    } on KYCApiException {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  /// Whether the applicant capture leg actually produced something to submit.
  bool get _applicantMediaCaptured =>
      state.selectedIdType != null &&
      (state.mediaIds.selfie != null ||
          state.mediaIds.documentFront != null ||
          (state.idNumber ?? '').trim().isNotEmpty);

  /// The applicant's OWN verification — an ordinary INDIVIDUAL submission: the
  /// leg's effective country, the ID they picked, their captured media, and
  /// `metadata.userId = applicantKeyPersonId` (the server-side link back to the
  /// application). The KYB workflow itself is never stamped on it (it is not an
  /// individual flow) — but when the org mapped an applicant workflow
  /// (business.applicant.workflowId), THAT id rides along so the server applies
  /// the mapped workflow's gates, pricing and decision graph.
  Future<void> _submitApplicantVerification(
    String country,
    String applicantKeyPersonId,
  ) async {
    final idTypeConfig = state.selectedIdType;
    if (idTypeConfig == null) return;
    final idNumber = idTypeConfig.requiresDocumentCapture
        ? null
        : (state.idNumber?.trim().isEmpty ?? true)
            ? null
            : state.idNumber!.trim();

    // Name: values typed on the id-input step (or the consumer's prop) win; the
    // applicant-role step's optional full name fills the gaps.
    final split = splitFullName(state.applicantName ?? '');
    final resolved = resolveVerifyUserData(_config.userData, state.userData);
    final firstName = resolved?.firstName ?? split?.firstName;
    final lastName = resolved?.lastName ?? split?.lastName;

    final mediaIds = state.mediaIds;
    // Deliberately NO sessionId: a session carries ONE submitted verification
    // and the business application has already claimed this one. The applicant
    // leg links back through metadata.userId instead.
    final request = VerifyRequest(
      country: country,
      idType: idTypeConfig.key,
      workflowId: _config.applicantWorkflowId,
      idNumber: idNumber,
      userData: (firstName != null || lastName != null)
          ? VerifyUserData(
              firstName: firstName,
              lastName: lastName,
              dateOfBirth: resolved?.dateOfBirth,
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
      deviceIntelligence: _config.deviceIntelligence,
      // The chip read, when the leg ran the NFC step (an overlaid applicant
      // workflow can enable it). Same validate-and-drop as the main submit.
      // Built by the SHARED builder, not a second copy of the block: a
      // hand-rolled twin drifts silently, and the applicant's chip must reach
      // the server in the same shape as everyone else's.
      nfc: (state.nfcChipData != null && idTypeConfig.supportsNfc)
          ? _nfcPayload(state.nfcChipData!)
          : null,
      metadata: VerifyMetadata(
        requestId: _uuid.v4(),
        // The link back to the application. Written AFTER the consumer's
        // metadata so nothing they passed can clobber it.
        extra: {...?_extraMetadata(), 'userId': applicantKeyPersonId},
        device: await _collectDeviceMetadata(),
      ),
    );

    await withRetry(() => api.verify(request));
  }

  Future<KYCSubmissionResult> submitAsync({
    void Function(int attempt, int total)? onRetry,
  }) async {
    if (_config.subjectType == 'business') {
      return _submitBusiness(onRetry: onRetry);
    }

    // A MULTI-ID run has no current selection by the time it submits: every
    // check committed its own slot and cleared the picker for the next one, so
    // the run's ID types live on the slots. Requiring a live selection here
    // refused EVERY multi-ID submission with "No ID type selected" — the run
    // was walked in full, the documents were uploaded, and the submit was
    // rejected by the client before a request was ever made.
    final idTypeConfig = state.selectedIdType;
    final committedSlots = state.multiIdSlots;
    // Scoped flows never pick an ID — the transport marker stands in.
    if (idTypeConfig == null && committedSlots.isEmpty && configScope(_config.scope) == null) {
      throw const KYCApiException(
        statusCode: 0,
        error: 'invalid_state',
        message: 'No ID type selected',
      );
    }

    // Number-only IDs require a typed-in idNumber and must pass format
    // validation. Only for the SINGLE-ID path: each multi-ID check validated
    // its own evidence at its own step, and its number rides its own slot.
    String? idNumber = state.idNumber;
    if (idTypeConfig != null) {
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
    }

    state = state.copyWith(isLoading: true);

    final requestId = _uuid.v4();
    // The org's user reference is the typed top-level `userId` field (becomes
    // Entity.externalUserId at the KYC seam). `metadata` is free-form passthrough.
    final userId = _config.userId;
    final extraMeta = <String, String>{
      ...?_extraMetadata(),
      // The address flow's Test-result pick (dev/sandbox tabs on the review
      // step). Ignored by production, so it is safe to send whenever set.
      if ((state.addressSandboxOutcome ?? '').isNotEmpty)
        'sandboxOutcome': state.addressSandboxOutcome!,
    };
    final deviceMetadata = await _collectDeviceMetadata();

    final mediaIds = state.mediaIds;

    // Multi-ID: every check was committed as a slot, and the whole run submits
    // as ONE verification the server judges by the pass policy. The FIRST slot
    // fills the single-ID fields.
    final multiSlots = state.multiIdSlots.length >= 2 ? state.multiIdSlots : null;
    final primary = multiSlots?.first;

    final request = VerifyRequest(
      sessionId: state.sessionId,
      country: effectiveCountry(_config, state),
      // Scoped flows carry the scope's transport marker instead of a picked
      // ID — the server requires a published workflow of the matching scope.
      idType: configScope(_config.scope) != null
          ? kScopeIdTypes[configScope(_config.scope)]!
          : (primary?.idType ?? idTypeConfig?.key ?? ''),
      idNumber: primary?.idNumber ?? idNumber,
      // Each check carries its OWN chip read — a top-level payload could only
      // ever be attributed to the primary check.
      idChecks: multiSlots
          ?.map((slot) => {
                ...slot.toWire(),
                if (slot.chipData != null)
                  'nfc': _nfcPayload(slot.chipData!).toJson(),
              })
          .toList(growable: false),
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
              // Multi-ID: the slot documents ride idChecks; only the RUN-level
              // media (the one selfie and its video) sit at the top level.
              // Sending a slot's document here too would file the last ID's
              // capture as though it were the verification's own.
              documentFront: multiSlots == null ? mediaIds.documentFront : null,
              documentBack: multiSlots == null ? mediaIds.documentBack : null,
              selfie: mediaIds.selfie,
              documentFrontVideo: mediaIds.documentFrontVideo,
              documentBackVideo: mediaIds.documentBackVideo,
              livenessVideo: mediaIds.livenessVideo,
              proofOfAddress: mediaIds.proofOfAddress,
              addressPhoto: mediaIds.addressPhoto,
            )
          : null,
      questionnaire: state.questionnaireAnswers.isNotEmpty
          ? state.questionnaireAnswers
          : null,
      proofOfAddressType:
          mediaIds.proofOfAddress != null ? state.poaDocumentType : null,
      // The smart address, when the step gathered one — the server validates
      // it against the workflow either way. Mirrors the RN buildVerifyRequest.
      address: state.address != null
          ? addressPayload(state.address!, config: _config.addressCollection)
          : null,
      deviceIntelligence: _config.deviceIntelligence,
      contact: (state.emailToken != null || state.phoneToken != null)
          ? VerifyContact(
              emailToken: state.emailToken,
              phoneToken: state.phoneToken,
            )
          : null,
      // Validate-and-drop: only send chip data for a chip-capable selected ID
      // (mirrors the server, which drops the block for non-chip IDs).
      nfc: (multiSlots == null &&
              state.nfcChipData != null &&
              (idTypeConfig?.supportsNfc ?? false))
          ? _nfcPayload(state.nfcChipData!)
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

  Future<void> _startAttemptSession() async {
    try {
      // The device id is the anonymous-mount resume fallback: without a
      // userId the server has nothing else to find the previous attempt by,
      // and every relaunch minted a fresh session. Hashed server-side.
      final deviceRef = await FingerprintService.instance.persistentDeviceId();
      // What this phone is, sent up front: the dashboard's in-progress row
      // shows Device and Source from the moment the SDK loads.
      final device = await DeviceMetadataService.instance.collect().catchError((_) => <String, dynamic>{});
      final res = await api.startSession(
        externalUserId: _config.userId ?? _config.metadata?['userId'],
        workflowId: _config.workflowId,
        deviceRef: deviceRef,
        device: device,
      );
      state = state.copyWith(sessionId: res.sessionId, sessionUrl: res.url);
      // Resuming: put the user back where they were, exactly as web does.
      // The stored snapshot hydrates the state (session_restore.dart), so
      // their step, captures and typed data survive an app restart.
      final progress = res.progress;
      if (progress != null && progress.isNotEmpty) {
        state = restoredState(
          state,
          progress,
          // The country the flow would use anyway — without it a session whose
          // applicant never picked one cannot rebuild its ID type.
          fallbackCountry: effectiveCountry(_config, state),
          // What the address flow offers THIS time. A workflow republished with
          // its photo slot off, or a platform that stopped serving search, no
          // longer has the screen the snapshot names.
          offeredAddressSteps: addressStepsFor(_config, state),
          // Where the applicant goes when the flow has no address region at
          // all: the first step AFTER where the region would sit that the real
          // order actually contains. Computed from the order, never guessed.
          addressExit: _addressExitFor(state),
        );
      }
    } catch (_) {
      // Resuming is a convenience; verifying is not conditional on it.
    }
  }

  /// The step after the address region in the REAL order, for a resume whose
  /// flow no longer offers any address step. Questionnaire sits immediately
  /// after the region when present; submission is the floor.
  KYCStep? _addressExitFor(KYCState state) {
    final order = buildStepOrder(_config, state);
    for (final step in order) {
      if (step == KYCStep.questionnaire || step == KYCStep.submitted) return step;
    }
    return null;
  }

  void reset() {
    // Fresh step journey per session (mirrors the RN store's reset), opening
    // on the same step a fresh provider would, with the server facts kept.
    final serverConfig = state.serverConfig;
    final opening = openingStep(_config, serverConfig: serverConfig);
    StepLog.reset();
    StepLog.record(opening);
    resetCurrentFix();
    _progressTimer?.cancel();
    _lastSavedProgress = '';
    state = KYCState(currentStep: opening, serverConfig: serverConfig);
  }

  // ── Attempt-session progress ────────────────────────────────────────────
  //
  // Written as the user advances, debounced and deduped, mirroring the web
  // SDK's useSessionProgress. Untouched progress is never written: the
  // presence of stored progress IS "they started", and a save-on-mount would
  // make every opened flow look started.

  Timer? _progressTimer;
  String _lastSavedProgress = '';

  void _scheduleProgressSave(KYCState next) {
    if (next.sessionId == null) return;
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 800), () {
      final s = state;
      final sessionId = s.sessionId;
      if (sessionId == null) return;
      final payload = progressFromState(
        s,
        effectiveCountryValue: effectiveCountry(_config, s),
      );
      if (isUntouchedProgress(
        payload,
        openingStep: kStepWireNames[openingStep(_config, serverConfig: s.serverConfig)] ?? 'consent',
      )) {
        return;
      }
      final fingerprint = jsonEncode(payload);
      if (fingerprint == _lastSavedProgress) return;
      _lastSavedProgress = fingerprint;
      // Losing a save costs some re-typing on a future resume, never anything
      // now.
      api.saveProgress(sessionId, payload).catchError((_) {});
    });
  }

  /// The paid registry check for the typed company, run at selection so the
  /// register answers BEFORE the details screen asks the applicant to confirm
  /// what it said — and its key people arrive before that step asks for them
  /// (they also prefill it). Only a definitive "not on the register" stops the
  /// flow: everything else (a short balance, an outage, a spent lookup budget)
  /// continues and is checked at submission, exactly as before. Mirrors the
  /// web SDK's useBusinessCheck and the RN store's runBusinessCheck.
  Future<BusinessCheckResult> checkBusiness() async {
    final s = state;
    final registrationNumber = s.registrationNumber?.trim() ?? '';
    if (registrationNumber.isEmpty) return (canContinue: true, company: null);

    // Already checked this exact company — do not pay to be told again.
    //
    // Only a SETTLED answer is reused. 'unavailable' is deliberately not one:
    // an outage said nothing about the company, so a repeat press retries the
    // register rather than replaying the outage. And a remembered answer keeps
    // its meaning — a stored not_found still blocks.
    final normalized = registrationNumber.toUpperCase();
    final check = s.businessCheck;
    final settled = check.status != 'idle' &&
        check.status != 'checking' &&
        check.status != 'unavailable';
    if (check.checkedNumber == normalized && settled) {
      return (
        canContinue: check.status != 'not_found',
        company: check.company,
      );
    }

    // No session means no anchor for the charge, so there is nothing to run
    // against. The check happens at submission, exactly as it did before.
    final sessionId = s.sessionId;
    if (sessionId == null) return (canContinue: true, company: null);

    state = s.copyWith(
      businessCheck:
          check.copyWith(status: 'checking', checkedNumber: normalized),
    );
    try {
      final registrationName = (s.registrationName ?? '').trim();
      final res = await api.businessSelect(
        sessionId: sessionId,
        country: s.businessCountry ?? _config.business?.country ?? '',
        subdivisionCode: s.businessSubdivisionCode,
        registrationNumber: registrationNumber,
        registrationName: registrationName.isEmpty ? null : registrationName,
        product: s.businessProduct,
      );
      if (!res.checked) {
        // The organisation could not be charged. Not the applicant's problem
        // and not something they can fix, so it is not shown as an error — the
        // flow continues and the check runs at submission.
        // `lookup_limit_reached` is the one they DID cause, by re-picking
        // company after company, and the one they can act on: check the number
        // rather than keep trying.
        state = state.copyWith(
          businessCheck: state.businessCheck.copyWith(
            status: res.reason == 'lookup_limit_reached'
                ? 'limit_reached'
                : 'skipped',
          ),
        );
        return (canContinue: true, company: null);
      }
      if (!res.found) {
        // A definitive "not on the register" is worth stopping for: continuing
        // would spend the applicant's time on documents for a company that
        // will fail anyway.
        state = state.copyWith(
          businessCheck: state.businessCheck.copyWith(
            status: 'not_found',
            clearCompany: true,
            officers: const [],
          ),
        );
        return (canContinue: false, company: null);
      }
      final company = res.business;
      state = state.copyWith(
        businessCheck: state.businessCheck.copyWith(
          status: 'found',
          company: company,
          officers: res.officers,
        ),
      );
      // Start the key-people step from the register's own officer list, so it
      // is a confirmation rather than a memory test. Applied at ARRIVAL rather
      // than at step mount (the screen is stateless) — same outcome, same
      // guard: never over anything the applicant has typed.
      if (res.officers.isNotEmpty && shouldPrefill(state.keyPeople)) {
        state = state.copyWith(
          keyPeople: prefillKeyPeople(
            res.officers,
            state.businessCountry ?? _config.business?.country ?? '',
          ),
        );
      }
      return (canContinue: true, company: company);
    } catch (_) {
      // A register outage is NOT "this company does not exist" — telling the
      // applicant their business is unregistered on the strength of a 503 is
      // the one wrong answer here. Retryable, and it never blocks: the check
      // still happens at submission.
      state = state.copyWith(
        businessCheck: state.businessCheck.copyWith(status: 'unavailable'),
      );
      return (canContinue: true, company: null);
    }
  }
}
