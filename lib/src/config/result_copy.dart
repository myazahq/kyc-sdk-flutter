import 'biometric_copy.dart';
import 'result_wait.dart';
import '../i18n/translate.dart' show TextFn, defaultTextFn;

// ─── What the terminal screens say ──────────────────────────────────────────
//
// Pure so it is testable without Flutter. The server's own reason wins on a
// decline or an error when it sent one: it is written for the applicant.
// UK English, no em dashes (user-facing copy rule). The words are catalogue
// texts ([TextFn], defaults in i18n/), and the org's biometric.copy fields
// ride as their older fields, so they still win. Mirrors the web SDK.

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
  TextFn t = defaultTextFn,
}) {
  final prefix = _waitingKeyFor(scope, waitsForResult);
  final title = t('$prefix.title', legacy: override?.title);
  if (retry != null) {
    return WaitingCopy(
      title: title,
      description: 'Connection issue, retrying (${retry.attempt}/${retry.total}).',
    );
  }
  return WaitingCopy(
      title: title, description: t('$prefix.description', legacy: override?.description));
}

String _waitingKeyFor(String? scope, bool waitsForResult) {
  if (scope == 'biometric-authentication') {
    return waitsForResult ? 'result.faceCheck.checking' : 'result.faceCheck.sending';
  }
  if (scope == 'biometric-enrollment') return 'result.faceEnrolment.saving';
  return 'result.submitting';
}

ResultCopy _screen(ResultTone tone, TextFn t, String prefix, [BiometricCopyText? over]) =>
    ResultCopy(
      tone: tone,
      title: t('$prefix.title', legacy: over?.title),
      description: t('$prefix.description', legacy: over?.description),
    );

/// What the person is told, per outcome. The server's own reason wins on a
/// decline or an error when it sent one; it is written for the applicant.
/// [verified] and [declined] are the org's own words for the two verdict
/// screens: on a decline its description wins even over the server's reason,
/// since the org chose to say that (as does the workflow's own text for it).
ResultCopy describeOutcome(
  VerificationOutcome outcome, {
  BiometricCopyText? verified,
  BiometricCopyText? declined,
  TextFn t = defaultTextFn,
}) {
  switch (outcome) {
    case TimedOutOutcome():
      return _screen(ResultTone.info, t, 'result.faceCheck.timeout');
    case SettledOutcome(:final status, :final reason):
      switch (status) {
        case 'approved':
          return _screen(ResultTone.success, t, 'result.faceCheck.verified', verified);
        case 'declined':
          final words = _screen(ResultTone.error, t, 'result.faceCheck.declined', declined);
          final orgChose = declined?.description != null ||
              words.description != defaultTextFn('result.faceCheck.declined.description');
          return ResultCopy(
            tone: ResultTone.error,
            title: words.title,
            description: orgChose ? words.description : (reason ?? words.description),
          );
        case 'in_review':
          return _screen(ResultTone.info, t, 'result.faceCheck.inReview');
        case 'error':
          return ResultCopy(
            tone: ResultTone.error,
            title: 'Something went wrong',
            description: reason ?? "We couldn't complete your check. Please try again in a moment.",
          );
        default:
          return _screen(ResultTone.info, t, 'result.faceCheck.submitted');
      }
  }
}
