import '../providers/kyc_state.dart';

// A resumed session restores the selfie's mediaId, but never the liveness claim
// that says how the selfie was taken: it lives in memory and is gone after a
// restart. A selfie with no claim behind it is not proof of a live person, and
// the server refuses a face re-authentication without one. So on restore the
// selfie is left out and, when the saved step comes after liveness, the person
// is sent back to take it again.
//
// Same rule as the web SDK's lib/liveness-resume.ts and the React Native SDK's
// lib/livenessResume.ts. Change all three together.

/// Steps that, once a selfie exists, can only be reached after liveness.
const Set<KYCStep> _afterLiveness = {
  KYCStep.supportingDocuments,
  KYCStep.proofOfAddress,
  KYCStep.addressSearch,
  KYCStep.addressCollection,
  KYCStep.addressEntrance,
  KYCStep.addressReview,
  KYCStep.questionnaire,
  KYCStep.submitted,
};

/// PURE. Where to resume when the saved progress carried a selfie.
KYCStep resumeStepWithoutSelfie(KYCStep saved) =>
    _afterLiveness.contains(saved) ? KYCStep.liveness : saved;
