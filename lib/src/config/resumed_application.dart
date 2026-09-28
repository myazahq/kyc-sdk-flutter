import '../providers/kyc_state.dart';

// A KYB application whose BUSINESS half already committed, resumed before the
// applicant's own verification went through.
//
// The business submission claims the session: from then on the session is
// SUBMITTED, and the server refuses a NEW business submission on it
// ("Start or resume this business verification session before submitting").
// That is what an applicant met after their phone died between the two legs
// (2026-09-28): the reopened flow walked them through the application again
// and sent it under a fresh request id, and it was refused.
//
// Session start hands back what it needs to recover instead: the parent's own
// request id. Replaying it is answered from the row that already exists, with
// the applicant KeyPerson id, and the applicant's own verification then goes
// through as it would have.
//
// Same rule as the web SDK's lib/resumed-application.ts. Change both together.

class ResumedApplication {
  /// The committed business verification.
  final String verificationId;

  /// The applicant KeyPerson still waiting on their own verification.
  final String applicantKeyPersonId;

  /// The business submission's own request id, replayed as-is.
  final String requestId;

  const ResumedApplication({
    required this.verificationId,
    required this.applicantKeyPersonId,
    required this.requestId,
  });
}

/// PURE. The resumed application a session-start response names, else null.
ResumedApplication? resumedApplicationFrom({
  Object? applicantKeyPersonId,
  Object? parentVerificationId,
  Object? parentRequestId,
}) {
  if (applicantKeyPersonId is! String || applicantKeyPersonId.isEmpty) return null;
  if (parentVerificationId is! String || parentVerificationId.isEmpty) return null;
  if (parentRequestId is! String || parentRequestId.isEmpty) return null;
  return ResumedApplication(
    verificationId: parentVerificationId,
    applicantKeyPersonId: applicantKeyPersonId,
    requestId: parentRequestId,
  );
}

/// PURE. The request id the business submission goes out under: a resumed
/// application replays the parent's; anything else is new.
String businessRequestId(ResumedApplication? resumed, String Function() fresh) =>
    resumed?.requestId ?? fresh();

/// PURE. Where a resumed application picks up: the start of the applicant's
/// own capture leg (the step after the applicant-role step in the REAL order).
/// The business half is done, so walking it again only invites a second
/// application; and the selfie is always taken again after a restart
/// (config/liveness_resume.dart). Null when the order has no applicant leg, in
/// which case the ordinary restore stands.
KYCStep? applicantLegStart(List<KYCStep> order) {
  final role = order.indexOf(KYCStep.applicantRole);
  if (role < 0 || role + 1 >= order.length) return null;
  final next = order[role + 1];
  return next == KYCStep.submitted ? null : next;
}
