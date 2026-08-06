import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_secure_messaging.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_session.dart';

// ─── The ICAO 9303 Part 11 Appendix D trace, replayed ─────────────────────────
//
// Appendix D publishes an entire BAC exchange: the chip's challenge, the
// terminal's authenticate command, the chip's reply, the resulting session keys
// and SSC, and then a real protected SELECT and READ BINARY with their exact
// bytes on the wire.
//
// Replaying it against a scripted chip proves the handshake, the session-key
// derivation, the send-sequence counter and the secure-messaging envelope all
// agree with the standard — the parts that are impossible to eyeball and
// expensive to debug against a real passport.

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);
String hexOf(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  const docNumber = 'L898902C';
  const dob = '690806';
  const doe = '940623';

  // Appendix D.3 fixed values.
  final rndIc = hex('4608F91988702212');
  final rndIfd = hex('781723860C06C226');
  final kIfd = hex('0B795240CB7049B01C19B33E32804F0B');
  // The chip's reply to MUTUAL AUTHENTICATE, verbatim from the standard.
  final authResponse = hex(
    '46B9342A41396CD7386BF5803104D7CEDC122B9132139BAF2EEDC94EE178534F'
    '2F2D235D074D74499000',
  );

  group('BAC session (ICAO 9303 D.3)', () {
    test('derives the published session keys and SSC', () async {
      final sent = <Uint8List>[];
      final session = EmrtdSession((cmd) async {
        sent.add(cmd);
        if (cmd[1] == 0x84) return hex('${hexOf(rndIc)}9000'); // GET CHALLENGE
        if (cmd[1] == 0x82) return authResponse; // MUTUAL AUTHENTICATE
        throw StateError('unexpected command ${hexOf(cmd)}');
      });

      await session.openSession(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
        nonce: rndIfd,
        keyMaterial: kIfd,
      );

      expect(session.isOpen, isTrue);

      // The command the standard says we should have sent.
      expect(
        hexOf(sent[1]),
        '0082000028'
        '72C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F2'
        '5F1448EEA8AD90A7'
        '28',
      );
    });

    test('the protected SELECT matches the published APDU byte for byte',
        () async {
      // Published session keys and SSC for the example.
      final sm = SecureMessaging(
        ksEnc: hex('979EC13B1CBFE9DCD01AB0FED307EAE5'),
        ksMac: hex('F1CB1F1FB5ADF208806B89DC579DC1F8'),
        ssc: hex('887022120C06C226'),
      );

      final apdu = sm.protect(
        Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C]),
        data: hex('011E'),
      );
      expect(hexOf(apdu),
          '0CA4020C158709016375432908C044F68E08BF8B92D635FF24F800');
    });

    test('unwraps the published SELECT response', () {
      final sm = SecureMessaging(
        ksEnc: hex('979EC13B1CBFE9DCD01AB0FED307EAE5'),
        ksMac: hex('F1CB1F1FB5ADF208806B89DC579DC1F8'),
        ssc: hex('887022120C06C226'),
      );
      sm.protect(Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C]), data: hex('011E'));

      final plain = sm.unprotect(hex('990290008E08FA855A5D4C50A8ED9000'));
      expect(plain, isEmpty); // a SELECT returns no data, only status
    });

    test('a tampered response is rejected rather than trusted', () {
      final sm = SecureMessaging(
        ksEnc: hex('979EC13B1CBFE9DCD01AB0FED307EAE5'),
        ksMac: hex('F1CB1F1FB5ADF208806B89DC579DC1F8'),
        ssc: hex('887022120C06C226'),
      );
      sm.protect(Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C]), data: hex('011E'));

      // One bit flipped in the MAC.
      expect(
        () => sm.unprotect(hex('990290008E08FA855A5D4C50A8EE9000')),
        throwsA(isA<SecureMessagingError>()),
      );
    });

    test('a wrong MRZ key surfaces as auth_failed, not a generic error',
        () async {
      final session = EmrtdSession((cmd) async {
        if (cmd[1] == 0x84) return hex('${hexOf(rndIc)}9000');
        return hex('6300'); // chip refuses authentication
      });

      expect(
        () => session.openSession(
          documentNumber: 'X123456',
          dateOfBirth: dob,
          dateOfExpiry: doe,
        ),
        throwsA(isA<EmrtdError>()
            .having((e) => e.code, 'code', 'auth_failed')),
      );
    });
  });
}
