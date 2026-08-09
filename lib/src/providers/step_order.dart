import '../config/business_application.dart';
import '../config/kyc_config.dart';
import 'kyc_state.dart';

/// The effective country for the flow: the one picked in the country-select step
/// (multi-region), else the config's country. Every country-sensitive read
/// (ID-type filtering, validation, verify payload, liveness gating) goes through
/// this so a picked country flows through consistently.
///
/// Returns non-null: `config.country` is optional only so a `workflowId` mount
/// need not invent one, and `MyazaKYC.show` refuses to mount without a country
/// once the workflow has been merged in. The `?? ''` is unreachable in a mounted
/// flow — it exists so this stays total rather than forcing a bang operator into
/// every caller.
String effectiveCountry(MyazaKYCConfig config, KYCState state) =>
    state.selectedCountry ??
    config.country ??
    // KYB configs carry no individual `country` — the applicant's capture leg
    // falls back to the registry country until (or unless) one is picked.
    state.businessCountry ??
    config.business?.country ??
    '';

/// Whether the flow offers more than one country (→ a country-select step).
bool hasCountrySelectStep(MyazaKYCConfig config) =>
    (config.countries?.length ?? 0) > 1;

/// The self-selected key person's ID-issuing country (uppercase ISO-2), when
/// the applicant picked themselves AND that entry carries one. The applicant
/// leg then SKIPS the country-select step — they already answered "where was
/// your ID issued?" on the key-people step.
String? applicantSelfCountry(KYCState state) {
  final index = state.applicantKeyPersonIndex;
  if (index == null || index < 0 || index >= state.keyPeople.length) return null;
  final country = state.keyPeople[index].country.trim();
  return country.isEmpty ? null : country.toUpperCase();
}

/// Countries the country-select step offers: the workflow's `countries` when
/// configured, else the org's GRANTED countries from the server config — the
/// KYB applicant leg's case (business configs carry no individual country
/// list, and the applicant may hold an ID issued anywhere the org can
/// verify). Empty while the server config is still loading.
List<String> countrySelectOptions(MyazaKYCConfig config, KYCState state) {
  final configured = [
    for (final entry in config.countries ?? const <WorkflowCountryOption>[])
      entry.country.toUpperCase(),
  ];
  if (configured.isNotEmpty) return configured;
  if (state.serverConfig.status != ServerConfigStatus.ready) return const [];
  final seen = <String>{};
  for (final row in state.serverConfig.idTypes) {
    seen.add(row.country.toUpperCase());
  }
  return seen.toList();
}

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
  final requiresCapture = requiresCaptureFor(config, state);
  final hasLiveness = livenessEnabledFor(config, state);
  final hasQuestionnaire = config.questionnaire?.isActive ?? false;
  final hasEmailVerify = config.emailVerification?.enabled ?? false;
  final hasPhoneVerify = config.phoneVerification?.enabled ?? false;

  // Business (KYB) flow: the registry details plus whatever application
  // sections the workflow configures — no capture/liveness of its own. When the
  // workflow requires applicant verification, the ordinary individual capture
  // leg runs afterwards for the SUBMITTER's identity.
  if (config.subjectType == 'business') {
    final business = config.business;
    return [
      KYCStep.consent,
      if (hasEmailVerify) KYCStep.contactEmail,
      if (hasPhoneVerify) KYCStep.contactPhone,
      KYCStep.businessDetails,
      if (hasKeyPeopleCollection(business)) KYCStep.businessKeyPeople,
      if (hasBusinessDocumentsStep(business)) KYCStep.businessDocuments,
      if (hasApplicantVerification(business)) ...[
        KYCStep.applicantRole,
        // The applicant may hold an ID issued anywhere the org can verify —
        // more than one granted country means they pick theirs first, exactly
        // like a multi-region individual flow. Mirrors the web SDK. EXCEPT
        // when they picked themselves from the key people and that entry
        // carries a country — already answered, so the step is skipped.
        if (countrySelectOptions(config, state).length > 1 &&
            applicantSelfCountry(state) == null)
          KYCStep.countrySelect,
        KYCStep.idType,
        if (requiresCapture) KYCStep.documentCapture else KYCStep.idInput,
        if (hasNfcStep(config, state)) KYCStep.nfc,
        if (hasLiveness) KYCStep.liveness,
      ],
      if (hasQuestionnaire) KYCStep.questionnaire,
      KYCStep.submitted,
    ];
  }

  final hasCountrySelect = hasCountrySelectStep(config);
  final hasProofOfAddress = config.proofOfAddress?.enabled ?? false;
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
