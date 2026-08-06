import '../services/api_service.dart' show WorkflowFlowConfig;
import 'business.dart';
import 'contact_verification.dart';
import 'kyc_config.dart';
import 'nfc_config.dart';
import 'proof_of_address.dart';
import 'questionnaire.dart';

/// Merges a resolved workflow's config over the consumer's [base] config —
/// **flow wins** on every key it defines; props fill the gaps (so a dev can
/// still set e.g. `userData` the flow doesn't carry). `appearance` merges
/// shallowly, per-field. Mirrors the web SDK's `mergeWorkflowConfig`.
///
/// Runtime data (apiKey, devUrl, userId, userData, metadata) is never
/// flow-controlled — [MyazaKYCConfig.copyWith] doesn't expose those keys.
///
/// Only the keys the Flutter SDK currently supports are merged; later
/// workstreams (country-select, questionnaire, proof of address, NFC, liveness
/// modes, device intelligence) extend this as their config fields land — they
/// can read the untouched values from [WorkflowFlowConfig.raw] until then.
MyazaKYCConfig mergeWorkflowIntoConfig(
  MyazaKYCConfig base,
  WorkflowFlowConfig flow,
) {
  // Business (KYB) workflows carry no top-level country — fall back to the
  // registry country so downstream code that expects one never sees empty.
  String? country = flow.country;
  if (country == null && flow.subjectType == 'business') {
    final business = flow.raw['business'];
    if (business is Map) country = business['country'] as String?;
  }

  // Multi-region list (from the untouched payload). Flow-defined only; a
  // single-country flow leaves it null and behaves as before.
  List<WorkflowCountryOption>? countries;
  final rawCountries = flow.raw['countries'];
  if (rawCountries is List) {
    countries = rawCountries
        .whereType<Map>()
        .map((e) => WorkflowCountryOption.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  final rawQuestionnaire = flow.raw['questionnaire'];
  final questionnaire = rawQuestionnaire is Map
      ? QuestionnaireConfig.fromJson(rawQuestionnaire.cast<String, dynamic>())
      : null;

  final rawPoa = flow.raw['proofOfAddress'];
  final proofOfAddress = rawPoa is Map
      ? ProofOfAddressConfig.fromJson(rawPoa.cast<String, dynamic>())
      : null;

  final rawEmail = flow.raw['emailVerification'];
  final emailVerification = rawEmail is Map
      ? EmailVerificationConfig.fromJson(rawEmail.cast<String, dynamic>())
      : null;

  final rawPhone = flow.raw['phoneVerification'];
  final phoneVerification = rawPhone is Map
      ? PhoneVerificationConfig.fromJson(rawPhone.cast<String, dynamic>())
      : null;

  final rawNfc = flow.raw['nfc'];
  final nfc =
      rawNfc is Map ? NfcConfig.fromJson(rawNfc.cast<String, dynamic>()) : null;

  final rawBusiness = flow.raw['business'];
  final business = rawBusiness is Map
      ? WorkflowBusinessConfig.fromJson(rawBusiness.cast<String, dynamic>())
      : null;

  return base.copyWith(
    country: country,
    countries: countries,
    questionnaire: questionnaire,
    proofOfAddress: proofOfAddress,
    emailVerification: emailVerification,
    phoneVerification: phoneVerification,
    nfc: nfc,
    subjectType: flow.subjectType,
    business: business,
    livenessMode: flow.raw['livenessMode'] as String?,
    flashSequenceLength: (flow.raw['flashSequenceLength'] as num?)?.toInt(),
    deviceIntelligence: flow.raw['deviceIntelligence'] as bool?,
    // Flow-defined idTypes win wholesale (an empty list means "all granted",
    // the same "unset = all" semantic the id-type picker applies). Null = the
    // flow didn't define it, so the consumer's prop is kept.
    idTypes: flow.idTypes,
    enableSelfie: flow.enableSelfie,
    enableDocumentCapture: flow.enableDocumentCapture,
    allowDocumentUpload: flow.allowDocumentUpload,
    enableLiveness: flow.enableLiveness,
    showThemeToggle: flow.showThemeToggle,
    disableClose: flow.disableClose,
    appearance:
        MyazaKYCAppearance.mergeFromJson(base.appearance, flow.appearance),
    consent: flow.consent != null
        ? KYCConsentContent.fromJson(flow.consent!)
        : null,
    success: flow.success != null
        ? KYCSuccessContent.fromJson(flow.success!)
        : null,
    voiceGuidance: VoiceGuidanceConfig.fromDynamic(flow.voiceGuidance),
  );
}
