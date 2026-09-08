import '../config/address_collection.dart';
import '../config/address_flow.dart';
import '../config/business.dart';
import '../config/business_application.dart';
import '../config/id_types.dart';
import '../utils/step_log.dart';
import 'address_step_order.dart';
import 'kyc_state.dart';

// ─── Restoring a resumed attempt session ─────────────────────────────────────
//
// The inverse of progressFromState (session_progress.dart), mirroring the web
// SDK's RESTORE_PROGRESS reducer: a resumed session's stored snapshot puts the
// user back on the step they left, with their captures and typed data intact.
// Pure function so it tests without a provider or a network. Only fields the
// snapshot carries are touched — a partial or old snapshot degrades to
// restoring less, never to breaking the flow.

final Map<String, KYCStep> _stepsByWireName = {
  for (final e in kStepWireNames.entries) e.value: e.key,
};

ApplicantRole? _applicantRoleFromKey(String key) {
  for (final r in ApplicantRole.values) {
    if (r.key == key) return r;
  }
  return null;
}

KeyPersonEntry? _keyPersonFromJson(Map<String, dynamic> row) {
  final name = (row['name'] as String?)?.trim() ?? '';
  if (name.isEmpty) return null;
  final role = keyPersonRoleFromKey((row['role'] as String?) ?? '') ?? KeyPersonRole.director;
  return KeyPersonEntry(
    name: name,
    role: role,
    email: (row['email'] as String?) ?? '',
    country: (row['country'] as String?) ?? '',
    ownershipPct: row['ownershipPct'] != null ? '${row['ownershipPct']}' : '',
    isCorporate: row['isCorporate'] == true,
    registrationNumber: (row['registrationNumber'] as String?) ?? '',
    owners: [
      for (final o in (row['owners'] as List?) ?? const [])
        if (o is Map)
          KeyPersonOwnerEntry(
            name: (o['name'] as String?) ?? '',
            ownershipPct: o['ownershipPct'] != null ? '${o['ownershipPct']}' : '',
            email: (o['email'] as String?) ?? '',
            country: (o['country'] as String?) ?? '',
          ),
    ],
  );
}

/// Steps that cannot be walked without a resolved ID type.
///
/// Landing on one without it is a dead end rather than a rough edge: the ID
/// screen has no format to validate against and no endpoint to submit to, so
/// Continue never enables and the applicant cannot go forward OR be told why.
const _needsIdType = {KYCStep.idInput, KYCStep.documentCapture, KYCStep.nfc};

/// The terminal step is a RESULT, not a position, so it is never resumed onto.
///
/// A submission that FAILED still writes `submitted` as the last step reached,
/// and resuming there submits again, fails the same way, and writes it again:
/// closing the app and reopening lands straight back on the error with no way
/// forward. That trap is real and was hit by a workflow republished mid-flow,
/// where the applicant was walking one version and the server judged the
/// submission by a newer one.
///
/// Starting the flow again also re-resolves the workflow, so an applicant who
/// was mid-flight across a republish walks the CURRENT steps rather than
/// submitting against rules they were never shown.
const _neverResume = {KYCStep.submitted};

/// The state after hydrating [s] from a resumed session's stored [progress].
///
/// [fallbackCountry] is the country the flow would use if the applicant had
/// never picked one — `effectiveCountry`, which the whole runtime resolves
/// through. It matters because this SDK stores the ID type as a RESOLVED
/// definition rather than a key, so rebuilding it needs a country; a session
/// whose applicant never explicitly picked one stored no `selectedCountry`, the
/// ID type therefore could not be resolved, and the resume dropped them on the
/// ID-number screen with no ID type and a permanently disabled Continue.
/// [offeredAddressSteps] is what this mount's address flow actually contains
/// (`addressStepsFor`). A saved address step the flow no longer offers is
/// clamped onto the nearest one it does — see [resumeAddressStep]. Defaults to
/// empty, which leaves a saved address step alone: a caller that cannot say
/// what is offered must not be taken to mean "nothing is".
KYCState restoredState(
  KYCState s,
  Map<String, dynamic> progress, {
  String? fallbackCountry,
  List<KYCStep> offeredAddressSteps = const [],
  KYCStep? addressExit,
}) {
  final data = (progress['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final mediaIds = (progress['mediaIds'] as Map?)?.cast<String, dynamic>() ?? const {};
  final business = (data['business'] as Map?)?.cast<String, dynamic>() ?? const {};
  final app = (data['businessApplication'] as Map?)?.cast<String, dynamic>() ?? const {};
  final contact = (data['contact'] as Map?)?.cast<String, dynamic>() ?? const {};

  final step = _stepsByWireName[progress['step']];
  final country = (data['selectedCountry'] as String?) ??
      s.selectedCountry ??
      ((fallbackCountry?.isEmpty ?? true) ? null : fallbackCountry);
  final idTypeKey = data['selectedIdType'] as String?;

  final keyPeople = <KeyPersonEntry>[
    for (final row in (app['keyPeople'] as List?) ?? const [])
      if (row is Map)
        if (_keyPersonFromJson(row.cast<String, dynamic>()) case final KeyPersonEntry p) p,
  ];

  final idType = idTypeKey != null && country != null
      ? resolveIdTypeDefinition(country, idTypeKey)
      : s.selectedIdType;

  // Never resume onto a step the restored state cannot support. Whatever went
  // missing, sending the applicant back to pick their ID is somewhere they can
  // act; the ID screen without an ID type is somewhere they can only sit.
  final restored = step ?? s.currentStep;
  final target = _neverResume.contains(restored) ? s.currentStep : restored;
  // Same principle one flow along: an address step this mount no longer offers
  // is absent from the step order, so next and back are both no-ops and the
  // applicant is stranded. When the flow offers NO address steps at all (the
  // workflow was republished with address collection off), the applicant is
  // routed past the region to [addressExit], the step they would have reached
  // had they finished, never left on a screen the order cannot place.
  final inFlow = kAddressFlowOrder.contains(target)
      ? resumeAddressStep(target, offeredAddressSteps) ?? addressExit ?? target
      : target;
  final safeStep = idType == null && _needsIdType.contains(inFlow) ? KYCStep.idType : inFlow;

  return s.copyWith(
    currentStep: safeStep,
    mediaIds: s.mediaIds.copyWith(
      documentFront: (mediaIds['documentFront'] as String?) ?? s.mediaIds.documentFront,
      documentBack: (mediaIds['documentBack'] as String?) ?? s.mediaIds.documentBack,
      selfie: (mediaIds['selfie'] as String?) ?? s.mediaIds.selfie,
      proofOfAddress: (mediaIds['proofOfAddress'] as String?) ?? s.mediaIds.proofOfAddress,
      addressPhoto: (mediaIds['addressPhoto'] as String?) ?? s.mediaIds.addressPhoto,
    ),
    selectedCountry: country,
    selectedIdType: idType,
    idNumber: (data['idNumber'] as String?) ?? s.idNumber,
    businessCountry: (business['country'] as String?) ?? s.businessCountry,
    businessProduct: (business['product'] as String?) ?? s.businessProduct,
    registrationNumber: _nonEmpty(business['registrationNumber']) ?? s.registrationNumber,
    registrationName: _nonEmpty(business['registrationName']) ?? s.registrationName,
    businessAddress: _nonEmpty(business['address']) ?? s.businessAddress,
    businessEmail: _nonEmpty(business['email']) ?? s.businessEmail,
    businessPhone: _nonEmpty(business['phone']) ?? s.businessPhone,
    businessWebsite: _nonEmpty(business['website']) ?? s.businessWebsite,
    keyPeople: keyPeople.isNotEmpty ? keyPeople : s.keyPeople,
    applicantRole: app['applicantRole'] is String
        ? _applicantRoleFromKey(app['applicantRole'] as String) ?? s.applicantRole
        : s.applicantRole,
    applicantName: _nonEmpty(app['applicantName']) ?? s.applicantName,
    emailAddress: (contact['emailAddress'] as String?) ?? s.emailAddress,
    phoneNumber: (contact['phoneNumber'] as String?) ?? s.phoneNumber,
    emailToken: (contact['emailToken'] as String?) ?? s.emailToken,
    phoneToken: (contact['phoneToken'] as String?) ?? s.phoneToken,
    expiredContact: contact['expired'] is List
        ? (contact['expired'] as List).whereType<String>().toList()
        : s.expiredContact,
    questionnaireAnswers: data['questionnaireAnswers'] is Map
        ? {
            ...s.questionnaireAnswers,
            ...(data['questionnaireAnswers'] as Map).cast<String, dynamic>(),
          }
        : s.questionnaireAnswers,
    // The device fix is deliberately NOT restored: it is evidence of standing
    // somewhere at a MOMENT, so it is taken fresh at confirm. See
    // addressFromProgressJson, which coerces every other field on the way in.
    address: addressFromProgressJson(data['address']) ?? s.address,
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
