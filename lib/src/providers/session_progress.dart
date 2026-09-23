import '../config/address_collection.dart';
import '../providers/kyc_state.dart';
import '../config/business.dart';
import '../utils/step_log.dart';

// ─── The attempt session's progress snapshot ─────────────────────────────────
//
// Mirrors the web SDK's progressFromState so the dashboard's attempt page
// reads both without branching: step + captured media slots + what was typed.
// Pure functions, tested without a provider or a network.

/// The snapshot the server stores.
///
/// [effectiveCountryValue] is the country the flow is actually running in,
/// which is NOT always one the applicant picked — a single-region flow takes it
/// from the config and never sets `selectedCountry`. Storing only an explicit
/// pick left the snapshot unable to describe itself: this SDK keeps the ID type
/// as a resolved definition, so a reader with no country could not rebuild it
/// and resumed the applicant onto the ID screen with no ID type at all.
Map<String, dynamic> progressFromState(KYCState s, {String? effectiveCountryValue}) {
  final mediaIds = <String, String>{
    if (s.mediaIds.documentFront != null) 'documentFront': s.mediaIds.documentFront!,
    if (s.mediaIds.documentBack != null) 'documentBack': s.mediaIds.documentBack!,
    if (s.mediaIds.selfie != null) 'selfie': s.mediaIds.selfie!,
    if (s.mediaIds.proofOfAddress != null) 'proofOfAddress': s.mediaIds.proofOfAddress!,
    if (s.mediaIds.addressPhoto != null) 'addressPhoto': s.mediaIds.addressPhoto!,
  };
  return {
    'step': kStepWireNames[s.currentStep] ?? 'consent',
    'stepLog': StepLog.snapshot(),
    'mediaIds': mediaIds,
    'data': {
      if (s.selectedCountry != null)
        'selectedCountry': s.selectedCountry
      else if (effectiveCountryValue != null && effectiveCountryValue.isNotEmpty)
        'selectedCountry': effectiveCountryValue,
      if (s.selectedIdType != null) 'selectedIdType': s.selectedIdType!.key,
      if (s.idNumber != null && s.idNumber!.isNotEmpty) 'idNumber': s.idNumber,
      'business': {
        if (s.businessCountry != null) 'country': s.businessCountry,
        if (s.businessProduct != null) 'product': s.businessProduct,
        'registrationNumber': s.registrationNumber ?? '',
        'registrationName': s.registrationName ?? '',
        'address': s.businessAddress ?? '',
        'email': s.businessEmail ?? '',
        'phone': s.businessPhone ?? '',
        'website': s.businessWebsite ?? '',
      },
      'businessApplication': {
        'keyPeople': [for (final p in s.keyPeople) p.toJson()],
        'applicantRole': s.applicantRole?.key,
        'applicantName': s.applicantName ?? '',
      },
      'contact': {
        if (s.emailAddress != null) 'emailAddress': s.emailAddress,
        if (s.phoneNumber != null) 'phoneNumber': s.phoneNumber,
        if (s.emailToken != null) 'emailToken': s.emailToken,
        if (s.phoneToken != null) 'phoneToken': s.phoneToken,
        if (s.expiredContact.isNotEmpty) 'expired': s.expiredContact,
      },
      // The uploads, without their previews: a restored slot shows as
      // uploaded, which is what the mediaId is for. Preview bytes never ride
      // progress — the same rule the selfie keeps.
      if (s.supportingDocuments.isNotEmpty)
        'supportingDocuments': [
          for (final d in s.supportingDocuments)
            {'type': d.type, 'mediaId': d.mediaId},
        ],
      'questionnaireAnswers': s.questionnaireAnswers,
      // The smart address survives a resume — a placed pin is work done, and
      // so is the address the applicant picked for it. Richer than the wire
      // payload on purpose: the label's anchor and the answered keep/update
      // question are display reasoning the server never sees, but losing them
      // on a resume would ask the applicant to settle it all over again.
      if (s.address != null) 'address': addressProgressJson(s.address!),
    },
  };
}

/// Nothing needs saving until they move off the opening screen: the presence
/// of stored progress IS "they started". Judged against the flow's OPENING
/// step (`consent` unless the workflow switched it off, then the first real
/// step), or a consent-less flow would save on mount and every opened link
/// would read "In progress".
bool isUntouchedProgress(
  Map<String, dynamic> payload, {
  String openingStep = 'consent',
}) {
  if (payload['step'] != openingStep) return false;
  return (payload['mediaIds'] as Map).isEmpty;
}
