import '../i18n/translate.dart' show TextFn;

// ─── Liveness challenge types ─────────────────────────────────────────────────

// `hold` is Passive Liveness: hold still and look at the camera. It passes on
// its own after a steady moment, and the server's liveness model does the
// judging. Never part of the random gesture pool. Each value's `name` is its
// wire name in the liveness claim (`integrity.liveness.challenges`).
enum LivenessChallenge { nod, turn, blink, smile, hold }

// ─── Liveness phase state machine ─────────────────────────────────────────────

enum LivenessPhase {
  loading,         // Initializing camera + ML Kit
  positioning,     // "Position your face in the circle"
  challenge,       // Active gesture challenge
  challengePassed, // Brief green flash
  capturing,       // Auto-capturing selfie
  complete,        // All done, selfie stored
  failed,          // Timeout or face lost
}

// ─── Challenge config ─────────────────────────────────────────────────────────

class ChallengeConfig {
  final LivenessChallenge type;
  final String instruction;
  final int timeoutSeconds;

  const ChallengeConfig({
    required this.type,
    required this.instruction,
    required this.timeoutSeconds,
  });
}

// ─── Default challenge pool (same as web SDK) ─────────────────────────────────

const List<ChallengeConfig> kDefaultChallengePool = [
  ChallengeConfig(
    type: LivenessChallenge.nod,
    instruction: 'Kindly nod your head',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.turn,
    instruction: 'Kindly turn your head',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.blink,
    instruction: 'Blink your eyes',
    timeoutSeconds: 6,
  ),
  ChallengeConfig(
    type: LivenessChallenge.smile,
    instruction: 'Smile please',
    timeoutSeconds: 6,
  ),
];

/// Passive Liveness (`livenessMode: 'passive'`): the ONE prompt. The face holds
/// still in the circle for about two seconds (liveness/passive_hold.dart); the
/// recording and the selfie go to the server, where the liveness model decides.
const ChallengeConfig kHoldChallenge = ChallengeConfig(
  type: LivenessChallenge.hold,
  instruction: 'Hold still and look at the camera',
  timeoutSeconds: 10,
);

// ─── Customisable instructions ────────────────────────────────────────────────
//
// The positioning prompt and the default challenges are catalogue texts (see
// i18n/), so a workflow may reword them. The notifier keeps setting this SDK's
// wording; the screen swaps it for the workflow's at display (and speech)
// time. A consumer's own challenge pool has no key and reads as written.
const Map<String, String> kPresenceInstructionKeys = {
  'Position your face in the circle': 'presence.position.placeFace',
  'Kindly nod your head': 'presence.challenge.nod',
  'Kindly turn your head': 'presence.challenge.turn',
  'Blink your eyes': 'presence.challenge.blink',
  'Smile please': 'presence.challenge.smile',
  'Hold still and look at the camera': 'presence.challenge.hold',
};

/// [raw] as the workflow words it, when it is one of the keyed instructions.
String presenceInstruction(String raw, TextFn t) {
  final key = kPresenceInstructionKeys[raw];
  return key == null ? raw : t(key);
}
