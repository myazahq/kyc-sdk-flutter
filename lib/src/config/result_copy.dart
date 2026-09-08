import 'biometric_copy.dart';
import 'result_wait.dart';

// ─── What the terminal screens say ──────────────────────────────────────────
//
// Pure so it is testable without Flutter. The server's own reason wins on a
// decline or an error when it sent one: it is written for the applicant.
// UK English, no em dashes (user-facing copy rule). Mirrors the web and RN
// SDKs' result copy word for word; keep the three in lockstep.

enum ResultTone { success, error, info }

class ResultCopy {
  final ResultTone tone;
  final String title;
  final String description;
  const ResultCopy({required this.tone, required this.title, required this.description});
}

class WaitingCopy {
  final String title;
  final String description;
  const WaitingCopy({required this.title, required this.description});
}

/// The ONE loading screen after the capture. On a re-authentication that waits
/// for its verdict it spans the selfie upload, the submission and the poll, so
/// it names the check rather than any of the three steps behind it. A retry in
/// flight replaces the description, never the title: the person is still
/// waiting for the same thing. [override] is the org's own words for the
/// screen (config/biometric_copy.dart), field by field over the default.
WaitingCopy describeWaiting({
  required String? scope,
  required bool waitsForResult,
  ({int attempt, int total})? retry,
  BiometricCopyText? override,
}) {
  final base = _withWaitingOverride(_waitingCopyFor(scope, waitsForResult), override);
  if (retry != null) {
    return WaitingCopy(
      title: base.title,
      description: 'Connection issue, retrying (${retry.attempt}/${retry.total}).',
    );
  }
  return base;
}

WaitingCopy _waitingCopyFor(String? scope, bool waitsForResult) {
  if (scope == 'biometric-authentication') {
    return waitsForResult
        ? const WaitingCopy(
            title: "Checking it's you",
            description: 'Matching your selfie against the photo on record. This usually takes a few seconds.',
          )
        : const WaitingCopy(title: 'Sending your face check', description: 'This only takes a moment.');
  }
  if (scope == 'biometric-enrollment') {
    return const WaitingCopy(
      title: 'Saving your selfie',
      description: 'It becomes the reference for your future face checks.',
    );
  }
  return const WaitingCopy(title: 'Submitting your verification', description: 'Please wait a moment.');
}

WaitingCopy _withWaitingOverride(WaitingCopy base, BiometricCopyText? over) => over == null
    ? base
    : WaitingCopy(
        title: over.title ?? base.title,
        description: over.description ?? base.description,
      );

ResultCopy _withOverride(ResultCopy base, BiometricCopyText? over) => over == null
    ? base
    : ResultCopy(
        tone: base.tone,
        title: over.title ?? base.title,
        description: over.description ?? base.description,
      );

/// What the person is told, per outcome. The server's own reason wins on a
/// decline or an error when it sent one; it is written for the applicant.
/// [verified] and [declined] are the org's own words for the two verdict
/// screens: on a decline its description wins even over the server's reason,
/// since the org chose to say that.
ResultCopy describeOutcome(
  VerificationOutcome outcome, {
  BiometricCopyText? verified,
  BiometricCopyText? declined,
}) {
  switch (outcome) {
    case TimedOutOutcome():
      return const ResultCopy(
        tone: ResultTone.info,
        title: 'Still checking',
        description: "This is taking longer than usual. You'll be notified as soon as it's done.",
      );
    case SettledOutcome(:final status, :final reason):
      switch (status) {
        case 'approved':
          return _withOverride(
            const ResultCopy(
              tone: ResultTone.success,
              title: "You're verified",
              description: 'Your face matched the photo on record.',
            ),
            verified,
          );
        case 'declined':
          return _withOverride(
            ResultCopy(
              tone: ResultTone.error,
              title: "We couldn't confirm it's you",
              description: reason ?? "Your face didn't match the photo on record.",
            ),
            declined,
          );
        case 'in_review':
          return const ResultCopy(
            tone: ResultTone.info,
            title: 'Under review',
            description: "A reviewer will take a look. You'll be notified of the outcome.",
          );
        case 'error':
          return ResultCopy(
            tone: ResultTone.error,
            title: 'Something went wrong',
            description: reason ?? "We couldn't complete your check. Please try again in a moment.",
          );
        default:
          return const ResultCopy(
            tone: ResultTone.info,
            title: 'Check submitted',
            description: "You'll be notified of the result.",
          );
      }
  }
}
