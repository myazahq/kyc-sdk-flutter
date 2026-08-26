import 'dart:typed_data';

import 'emrtd_session.dart';

// ACTIVE AUTHENTICATION — asking the chip to prove it is not a copy.
//
// The Flutter port of the RN SDK's emrtd/activeAuth.ts. Keep the two in
// lockstep.
//
// Passive authentication (the SOD) proves the data was signed by the issuing
// state. It cannot prove this is the chip they signed it onto: copy a genuine
// passport's files onto a blank chip and every hash and signature still
// verifies, because none of them is bound to the silicon.
//
// So we ask the chip to SIGN something. Its private key never leaves it, and
// the matching public key sits in DG15 — which is itself hashed into the SOD,
// so the issuing state has vouched for it. A cloner can copy DG15; they cannot
// copy the key that answers for it.
//
// TWO THINGS MATTER HERE, and neither is visible from this file alone:
//
//   • THE CHALLENGE IS THE SERVER'S. We do not generate it. A nonce we chose
//     would let anyone replay one captured (challenge, signature) pair forever,
//     which is the clone this is meant to catch.
//   • WE DO NOT VERIFY. The signature is carried to the server untouched and
//     checked there against a SOD-bound DG15. A client that verified its own
//     chip would be a client an attacker can simply patch — the same reason
//     passive authentication has always run server-side.
//
// Both are also why this file is short: reading and forwarding is the whole job.

/// ICAO 9303-11 fixes the Active-Authentication challenge at 8 bytes.
const int aaChallengeBytes = 8;

/// EF.DG15 — the chip's Active-Authentication public key.
const int _efDg15 = 0x010F;

/// The server's challenge: its id (to spend) and its bytes (for the chip).
class AaChallenge {
  const AaChallenge({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
}

/// What the anti-clone step produced. Both null on the many chips that support
/// no Active Authentication at all.
class ActiveAuthRead {
  const ActiveAuthRead({this.dg15, this.signature});

  /// DG15 — the chip's AA public key, as raw file bytes.
  final Uint8List? dg15;

  /// The chip's signature over the server's challenge.
  final Uint8List? signature;

  bool get isEmpty => dg15 == null && signature == null;
}

/// Read DG15 and get the chip to sign the server's challenge.
///
/// Best-effort throughout, like every optional group: most chips in the field
/// support no Active Authentication at all, and reporting that as a problem
/// would flag the majority of genuine passports.
Future<ActiveAuthRead> readActiveAuth(
  EmrtdSession session,
  AaChallenge? challenge,
) async {
  // No challenge means the server could not issue one. Reading DG15 anyway
  // would cost a round trip on the document for a key nothing can be checked
  // against, so the whole step is skipped.
  if (challenge == null || challenge.bytes.length != aaChallengeBytes) {
    return const ActiveAuthRead();
  }

  Uint8List? dg15;
  try {
    dg15 = await session.readFile(_efDg15);
  } catch (_) {
    // Absent, or the chip left contact. Either way it costs this step alone.
    return const ActiveAuthRead();
  }

  final signature = await session.internalAuthenticate(challenge.bytes);
  // A chip that carries DG15 but will not sign is unusual and worth reporting
  // honestly: the server can then say "read the key, got no answer" rather
  // than "this chip has no AA".
  return ActiveAuthRead(dg15: dg15, signature: signature);
}
