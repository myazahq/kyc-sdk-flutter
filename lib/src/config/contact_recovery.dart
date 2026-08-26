// Recovery from a submit refused over contact proofs. Mirrors the web SDK's
// steps/contact-recovery.ts and the RN SDK's lib/contact-recovery.ts — keep
// the three in lockstep.
//
// Contact proof tokens are SINGLE-USE and expire ~30 minutes after the OTP is
// checked, but they ride session progress and are restored on resume. A
// resumed attempt therefore carries a proof the server will (rightly)
// validate-and-drop at submit, while the contact step still shows "verified"
// — and a plain retry resubmits the same dead token forever.
//
// The 422 is recoverable in-flow: clear the stale proofs, walk the person
// back to the contact step (their data is untouched), and once re-verified
// the step routes straight back to `submitted`, which auto-submits with the
// fresh token.
import '../providers/kyc_state.dart';
import '../services/api_service.dart';

/// The channels a 422 `contact_verification_required` names as missing.
List<String> expiredContactChannels(Object? err) {
  if (err is! KYCApiException || err.error != 'contact_verification_required') {
    return const [];
  }
  final missing = err.details?['missing'];
  if (missing is! List) return const [];
  return [
    for (final c in missing)
      if (c == 'email' || c == 'phone') c as String,
  ];
}

KYCStep contactStepFor(String channel) =>
    channel == 'email' ? KYCStep.contactEmail : KYCStep.contactPhone;

/// Where the step routes once this channel is verified. Null means the
/// ordinary forward walk; in recovery it returns to `submitted` (which
/// auto-submits with the fresh proof) via any OTHER still-refused channel
/// first, so the person never re-walks steps they already completed.
KYCStep? stepAfterContactVerified({
  required bool recovery,
  required List<String> expired,
  required String channel,
}) {
  if (!recovery) return null;
  final remaining = expired.where((c) => c != channel).toList();
  return remaining.isEmpty ? KYCStep.submitted : contactStepFor(remaining.first);
}
