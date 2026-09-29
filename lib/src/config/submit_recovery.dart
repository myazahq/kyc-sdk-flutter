import '../providers/kyc_state.dart' show KYCStep;

// ─── Going back from a refused submission ────────────────────────────────────
//
// A refused submission used to end on an error with only Close, while its own
// message said "go back and upload them". Closing lost the application. Most
// refusals are about something the applicant can fix (a missing document, a
// required field), so the error screen offers Go back to the step that owns it,
// and the flow resubmits when they return to the end.

/// The step that owns each refusal the server names. Add-only.
const Map<String, KYCStep> _stepForCode = {
  'missing_documents': KYCStep.businessDocuments,
  'missing_company_info': KYCStep.businessDetails,
  'key_people_required': KYCStep.businessKeyPeople,
  'missing_supporting_documents': KYCStep.supportingDocuments,
  'questionnaire_invalid': KYCStep.questionnaire,
  'proof_of_address_required': KYCStep.proofOfAddress,
  'address_collection_required': KYCStep.addressCollection,
  'missing_address_fields': KYCStep.addressCollection,
};

/// A capture the server could not accept, by the key it names.
const Map<String, KYCStep> _stepForMediaKey = {
  'documentFront': KYCStep.documentCapture,
  'documentBack': KYCStep.documentCapture,
  'selfie': KYCStep.liveness,
  'livenessVideo': KYCStep.liveness,
  'proofOfAddress': KYCStep.proofOfAddress,
  'addressPhoto': KYCStep.addressEntrance,
};

/// Refusals going back cannot fix: nothing the applicant entered is wrong.
const Set<String> _notRecoverable = {
  'invalid_api_key',
  'insufficient_credits',
  'feature_disabled',
  'business_not_approved',
  'rate_limited',
};

/// Where Go back should land for a refusal, or null when going back cannot
/// help. A named step is used only when this flow contains it; anything else
/// lands on the last step before submission, so the applicant can still walk
/// back through what they entered.
KYCStep? recoveryStepFor(
  String serverCode,
  List<KYCStep> order, {
  String? mediaKey,
}) {
  if (_notRecoverable.contains(serverCode)) return null;
  final named = _stepForCode[serverCode] ??
      (serverCode == 'invalid_media' && mediaKey != null ? _stepForMediaKey[mediaKey] : null);
  if (named != null && order.contains(named)) return named;
  final end = order.indexOf(KYCStep.submitted);
  if (end > 0) return order[end - 1];
  return null;
}
