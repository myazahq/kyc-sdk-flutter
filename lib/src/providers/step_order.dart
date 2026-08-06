import '../config/kyc_config.dart';
import 'kyc_state.dart';

/// The effective country for the flow: the one picked in the country-select step
/// (multi-region), else the config's country. Every country-sensitive read
/// (ID-type filtering, validation, verify payload, liveness gating) goes through
/// this so a picked country flows through consistently.
String effectiveCountry(MyazaKYCConfig config, KYCState state) =>
    state.selectedCountry ?? config.country;

/// Whether the flow offers more than one country (→ a country-select step).
bool hasCountrySelectStep(MyazaKYCConfig config) =>
    (config.countries?.length ?? 0) > 1;

/// Whether the NFC chip step applies to the selected ID: the config enables it,
/// the ID is chip-capable (`supportsNfc`), and the workflow's composite-key
/// selection (if any) includes it. Chip-capable IDs are document IDs, so this is
/// only ever true on the document-capture path.
bool hasNfcStep(MyazaKYCConfig config, KYCState state) {
  final nfc = config.nfc;
  if (nfc == null || !nfc.enabled) return false;
  final cfg = state.selectedIdType;
  if (cfg == null || !cfg.supportsNfc) return false;
  return nfc.selects(effectiveCountry(config, state), cfg.key);
}

// ─── Step order (single source of truth) ─────────────────────────────────────
//
// The ordered list of steps for the current config + state. Both navigation
// (KYCNotifier.nextStep/previousStep) and the progress bar read this, mirroring
// the web SDK's `buildStepOrder`. Optional steps are inserted only when their
// feature is enabled; each workstream flips its own `has*` gate on as it lands.

/// Whether the currently selected ID requires document capture (defaulting to
/// true until an ID is chosen, matching the web SDK), ANDed with the global
/// `enableDocumentCapture` flag.
bool requiresCaptureFor(MyazaKYCConfig config, KYCState state) {
  final requires = state.selectedIdType?.requiresDocumentCapture ?? true;
  return requires && config.enableDocumentCapture;
}

/// Whether liveness runs for the selected ID. The server per-ID `livenessCheck`
/// flag wins; falls back to the consumer's `enableLiveness`/`enableSelfie` when
/// the server config hasn't loaded.
bool livenessEnabledFor(MyazaKYCConfig config, KYCState state) {
  if (!config.enableLiveness || !config.enableSelfie) return false;
  final cfg = state.selectedIdType;
  if (cfg == null) return true;
  final features = state.serverConfig
      .featuresFor(effectiveCountry(config, state), cfg.key);
  if (features == null) return true; // server config not loaded — assume on
  return features.livenessCheck;
}

/// Builds the ordered step list for [config] + [state]. Recomputed on every
/// navigation, so a step that depends on later state (document-capture vs
/// id-input, per-ID liveness) resolves correctly once that state is known.
List<KYCStep> buildStepOrder(MyazaKYCConfig config, KYCState state) {
  // Business (KYB) flow: no capture/liveness — just the registry details, plus
  // an optional questionnaire.
  if (config.subjectType == 'business') {
    return [
      KYCStep.consent,
      KYCStep.businessDetails,
      if (config.questionnaire?.isActive ?? false) KYCStep.questionnaire,
      KYCStep.submitted,
    ];
  }

  final requiresCapture = requiresCaptureFor(config, state);
  final hasLiveness = livenessEnabledFor(config, state);

  final hasCountrySelect = hasCountrySelectStep(config);
  final hasQuestionnaire = config.questionnaire?.isActive ?? false;
  final hasProofOfAddress = config.proofOfAddress?.enabled ?? false;
  final hasEmailVerify = config.emailVerification?.enabled ?? false;
  final hasPhoneVerify = config.phoneVerification?.enabled ?? false;
  final hasNfc = hasNfcStep(config, state);

  return [
    KYCStep.consent,
    if (hasEmailVerify) KYCStep.contactEmail,
    if (hasPhoneVerify) KYCStep.contactPhone,
    if (hasCountrySelect) KYCStep.countrySelect,
    KYCStep.idType,
    if (requiresCapture) KYCStep.documentCapture else KYCStep.idInput,
    if (hasNfc) KYCStep.nfc,
    if (hasLiveness) KYCStep.liveness,
    if (hasProofOfAddress) KYCStep.proofOfAddress,
    if (hasQuestionnaire) KYCStep.questionnaire,
    KYCStep.submitted,
  ];
}
