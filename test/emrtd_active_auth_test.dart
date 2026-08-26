import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_active_auth.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_session.dart';

// Active Authentication — the chip proving it is the original, not a copy.
//
// The signature check itself is the SERVER's job (a client that verified its
// own chip could be patched to say yes), so what these cover is that the step
// asks for the right thing and degrades rather than failing: a chip read must
// never break because the anti-clone extra could not run.
//
// Mirrors the RN SDK's activeAuth tests. Keep the two in lockstep.

void main() {
  /// A session whose transceiver fails the test if anything is sent over it.
  EmrtdSession silentSession() => EmrtdSession((_) async {
        fail('nothing should be sent to the chip');
      });

  test('does nothing at all without a server challenge', () async {
    // Not a degraded read — a SKIPPED one. Reading DG15 for a key nothing can
    // be checked against costs a round trip on a document the user is holding.
    expect((await readActiveAuth(silentSession(), null)).isEmpty, isTrue);
  });

  test('refuses a challenge that is not 8 bytes — 9303-11 fixes the length',
      () async {
    final short = AaChallenge(id: 'c', bytes: Uint8List.fromList([1, 2, 3]));
    expect((await readActiveAuth(silentSession(), short)).isEmpty, isTrue);
  });

  test('a chip that will not give up DG15 simply has no AA', () async {
    // The overwhelming majority of chips in the field. Reporting absence as
    // anything but absence would flag most genuine passports — and it must
    // never throw into the read that has already banked DG1 and the SOD.
    final session = EmrtdSession((_) async => Uint8List.fromList([0x6a, 0x82]));
    final challenge = AaChallenge(
      id: 'chal_1',
      bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
    );
    final result = await readActiveAuth(session, challenge);
    expect(result.isEmpty, isTrue);
  });

  test('INTERNAL AUTHENTICATE answers null without a secure session', () async {
    // Never an exception: the caller is mid-read on a document somebody is
    // holding, and losing the anti-clone check is not losing the read.
    final signature = await silentSession()
        .internalAuthenticate(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    expect(signature, isNull);
  });
}
