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
  const ResubmitConfig({required this.steps, this.message, this.idType});

  /// Wire step names to redo. Never empty — the server omits the key instead.
  final List<String> steps;

  /// The reviewer's note to the applicant.
  final String? message;

  /// The ID the verification being redone used, when the server CARRIES it.
  ///
  /// A redo keeps the verification id, so a reviewer who did not tick the ID
  /// asked for nothing about it: the server keeps the original number,
  /// documents and chip read, and says so by sending the idType here. Present
  /// only on an individual, single-ID send-back whose reviewer did not tick
  /// 'id-type'. Absent keeps the old behaviour. Read through [keptIdType].
  final String? idType;

  static ResubmitConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final raw = json['steps'];
    if (raw is! List) return null;
    final steps = raw.whereType<String>().toList();
    if (steps.isEmpty) return null;
    final message = json['message'];
    final idType = json['idType'];
    return ResubmitConfig(
      steps: steps,
      message: message is String && message.trim().isNotEmpty ? message : null,
      idType: idType is String ? idType : null,
    );
  }
}

/// The ID a redo keeps, or null when the applicant must name one again.
///
/// Read defensively rather than trusted: an idType beside a plan that ticks the
/// ID picker, or beside no plan at all, is not an instruction to skip it.
String? keptIdType(ResubmitConfig? resubmit) {
  final asked = resubmit?.steps;
  if (asked == null || asked.isEmpty || asked.contains('id-type')) return null;
  final idType = resubmit?.idType;
  return (idType != null && idType.trim().isNotEmpty) ? idType : null;
}

/// Whether the server supplies the kept ID's evidence, so the submission names
/// the ID and nothing else: no number, no document media, no chip read.
///
/// True only when the ID is kept AND no evidence step was asked. A reviewer who
/// ticked the document or the number wants it again, and gets the ordinary
/// submission for it.
bool carriesIdEvidence(ResubmitConfig? resubmit) =>
    keptIdType(resubmit) != null &&
    !_evidence.any((step) => resubmit!.steps.contains(kStepWireNames[step]));

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
/// Unless the server carries the original ID ([keptIdType]), nothing is carried
/// forward from the verification being redone, so the applicant must still say
/// which ID this is and supply it. `POST /verify` requires an `idType`, and a number-only
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
  // A kept ID needs no picker and, unless the reviewer asked for the evidence,
  // no evidence step either: the redo is only what was ticked. KYB never keeps
  // an ID (the server never sends one for a business redo), so it stays as is.
  final isBusiness = order.contains(KYCStep.businessDetails);
  final required = isBusiness
      ? _businessRequired
      : (keptIdType(resubmit) != null ? const <KYCStep>{} : _individualRequired);
  for (final step in required) {
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
