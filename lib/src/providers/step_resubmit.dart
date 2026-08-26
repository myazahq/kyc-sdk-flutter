// Narrowing a flow to the steps a reviewer asked the applicant to redo.
//
// A reviewer looked at a finished verification and sent it back — usually
// because one thing was unreadable, not because everything was wrong. Making
// somebody retake a passport photo is reasonable; making them redo consent, the
// ID picker, liveness and a questionnaire to fix that photo is how you lose
// them.
//
// The instruction rides the session's config snapshot (`config.resubmit`), which
// is how every other per-session flow instruction travels. An SDK that predates
// this simply does not read the key and runs the whole flow, which is the safe
// degradation: asking for too much is recoverable, silently skipping a step the
// reviewer wanted is not.
//
// Mirrors the web SDK's `lib/resubmit.ts` and the RN SDK's `lib/resubmit.ts` —
// keep all three in lockstep.

import '../utils/step_log.dart' show kStepWireNames;
import 'kyc_state.dart' show KYCStep;

/// A reviewer's instruction to redo part of the flow.
class ResubmitConfig {
  const ResubmitConfig({required this.steps, this.message});

  /// Wire step names to redo. Never empty — the server omits the key instead.
  final List<String> steps;

  /// The reviewer's note to the applicant.
  final String? message;

  static ResubmitConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final raw = json['steps'];
    if (raw is! List) return null;
    final steps = raw.whereType<String>().toList();
    if (steps.isEmpty) return null;
    final message = json['message'];
    return ResubmitConfig(
      steps: steps,
      message: message is String && message.trim().isNotEmpty ? message : null,
    );
  }
}

/// Steps that are always kept, whatever the reviewer ticked.
///
/// [KYCStep.consent] because a flow with no first screen is disorienting, and it
/// is where the redo is explained. [KYCStep.submitted] because a flow has to end
/// somewhere. Neither is something the applicant is being asked to redo — they
/// are the frame around what is.
const Set<KYCStep> _always = {KYCStep.consent, KYCStep.submitted};

/// One ID's evidence — a FAMILY, not alternatives a reviewer picks between.
///
/// Which member a flow contains depends on the ID type: a number-only ID has
/// [KYCStep.idInput], a document ID has [KYCStep.documentCapture] (and maybe
/// [KYCStep.nfc]). At the moment the order is built nobody has chosen one yet,
/// so the flow is shaped by a default. A plan naming `id-input` against an order
/// still shaped for `document-capture` therefore matched NOTHING, fell through
/// to the safety net, and silently ran the entire flow — which a reviewer sees
/// as "I asked for the ID and it made them do everything again".
const Set<KYCStep> _evidence = {
  KYCStep.idInput,
  KYCStep.documentCapture,
  KYCStep.nfc,
};

/// Steps a narrowed flow keeps regardless, because without them it cannot
/// produce a submission at all.
///
/// A resubmission is a NEW verification on a FRESH session: nothing is carried
/// forward from the one being redone, so the applicant must still say which ID
/// this is and supply it. `POST /verify` requires an `idType`, and a number-only
/// ID requires the number with it.
///
/// So narrowing removes the things arranged AROUND the identity — liveness,
/// proof of address, the questionnaire, contact checks — and never the identity
/// itself. The alternative is a two-screen flow that collects a photo and then
/// fails to submit.
const Set<KYCStep> _individualRequired = {KYCStep.idType, ..._evidence};
const Set<KYCStep> _businessRequired = {KYCStep.businessDetails};

/// Narrow a full step order to the redo, preserving flow order.
///
/// Order comes from [order], never from the reviewer's list: they ticked
/// checkboxes, and walking somebody through liveness before document capture
/// because that is the order the boxes were ticked in would be nonsense.
///
/// Returns the ORIGINAL order untouched when the instruction is absent, empty,
/// or matches nothing we know. That last case matters: a server that learns a
/// new step name before this SDK does must not produce a two-screen flow that
/// collects nothing.
List<KYCStep> applyResubmitSteps(List<KYCStep> order, ResubmitConfig? resubmit) {
  final asked = resubmit?.steps;
  if (asked == null || asked.isEmpty) return order;

  final wantsEvidence =
      _evidence.any((step) => asked.contains(kStepWireNames[step]));

  // Does the instruction name anything this flow actually has? If not, it came
  // from a server that knows a step name this SDK does not — and narrowing on it
  // would quietly drop whatever was really asked for. Checked BEFORE the
  // required steps are added, or those alone would make every unknown plan look
  // recognised and turn the safety net below into dead code.
  final recognised = wantsEvidence ||
      order.any((step) => asked.contains(kStepWireNames[step]));
  if (!recognised) return order;

  final wanted = asked.toSet();
  if (wantsEvidence) {
    for (final step in _evidence) {
      final name = kStepWireNames[step];
      if (name != null) wanted.add(name);
    }
  }
  for (final step in order.contains(KYCStep.businessDetails)
      ? _businessRequired
      : _individualRequired) {
    final name = kStepWireNames[step];
    if (name != null) wanted.add(name);
  }

  final narrowed = order
      .where((step) => wanted.contains(kStepWireNames[step]) || _always.contains(step))
      .toList();

  // Nothing but the frame survived, so the instruction named steps this flow
  // does not contain. Run everything rather than nothing.
  final collects = narrowed.any((step) => !_always.contains(step));
  return collects ? narrowed : order;
}

/// The reviewer's note to the applicant, when this mount is a targeted redo.
///
/// The dashboard's send-back dialog asks a reviewer to explain the problem — its
/// placeholder is literally "Your document photo was too dark to read, please
/// retake it in good light." The server stamps that note onto the session and
/// every SDK parses it into config, and until now NONE of them displayed it. So
/// a send-back reached the applicant as a flow that had silently lost most of
/// its steps, with nothing saying why they were back or what to do differently.
///
/// Returns null when there is nothing to show, so a caller can render this
/// unconditionally. Mirrors the web and RN SDKs' `resubmitNote`.
String? resubmitNote(ResubmitConfig? resubmit) {
  if (resubmit == null || resubmit.steps.isEmpty) return null;
  final note = resubmit.message?.trim();
  return (note != null && note.isNotEmpty) ? note : null;
}
