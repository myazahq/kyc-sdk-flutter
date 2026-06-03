// ─── Liveness challenge types ─────────────────────────────────────────────────

enum LivenessChallenge { nod, turn, blink, smile }

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
