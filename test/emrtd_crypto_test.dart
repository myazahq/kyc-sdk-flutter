import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_crypto.dart';

// ─── ICAO 9303 Part 11, Appendix D — the official BAC worked example ──────────
//
// The standard publishes a complete trace of a BAC session: the MRZ input, the
// derived keys, the random nonces, and every intermediate value. That makes the
// whole of our crypto verifiable WITHOUT a passport, which is the difference
// between "it compiles" and "it is correct".
//
// If any of these fail, the implementation is wrong — not the test.

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

String hexOf(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  // Appendix D.2 — MRZ of the example document.
  const docNumber = 'L898902C';
  const dob = '690806';
  const doe = '940623';

  group('BAC key derivation (ICAO 9303 D.2)', () {
    test('MRZ information is assembled with check digits', () {
      expect(
        mrzKeySeedInput(
          documentNumber: docNumber,
          dateOfBirth: dob,
          dateOfExpiry: doe,
        ),
        'L898902C<3' '6908061' '9406236',
      );
    });

    test('Kseed matches the published value', () {
      final seed = keySeed(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
      expect(hexOf(seed), '239AB9CB282DAF66231DC5A4DF6BFBAE');
    });

    test('Kenc and Kmac match the published values', () {
      final seed = keySeed(
        documentNumber: docNumber,
        dateOfBirth: dob,
        dateOfExpiry: doe,
      );
      expect(hexOf(deriveKey(seed, 1)), 'AB94FDECF2674FDFB9B391F85D7F76F2');
      expect(hexOf(deriveKey(seed, 2)), '7962D9ECE03D1ACD4C76089DCE131543');
    });
  });

  group('primitives', () {
    test('padding follows ISO 9797-1 method 2', () {
      expect(hexOf(pad(hex('01020304'))), '0102030480000000');
      // A full block still gets a whole block of padding.
      expect(hexOf(pad(hex('0102030405060708'))),
          '01020304050607088000000000000000');
    });

    test('unpad reverses it, and leaves unpadded data alone', () {
      expect(hexOf(unpad(hex('0102030480000000'))), '01020304');
      expect(hexOf(unpad(hex('01020304'))), '01020304');
    });

    test('3DES-CBC round-trips', () {
      final key = deriveKey(
        keySeed(
          documentNumber: docNumber,
          dateOfBirth: dob,
          dateOfExpiry: doe,
        ),
        1,
      );
      final plain = pad(hex('0011223344556677'));
      final enc = desEde2Cbc(key, plain, encrypt: true);
      expect(hexOf(desEde2Cbc(key, enc, encrypt: false)), hexOf(plain));
    });
  });

  group('mutual authentication (ICAO 9303 D.3)', () {
    // The example's fixed nonces and keying material.
    final rndIc = hex('4608F91988702212');
    final rndIfd = hex('781723860C06C226');
    final kIfd = hex('0B795240CB7049B01C19B33E32804F0B');

    final kEnc = hex('AB94FDECF2674FDFB9B391F85D7F76F2');
    final kMac = hex('7962D9ECE03D1ACD4C76089DCE131543');

    test('the command data encrypts to the published E.IFD', () {
      final s = Uint8List.fromList([...rndIfd, ...rndIc, ...kIfd]);
      final eIfd = desEde2Cbc(kEnc, s, encrypt: true);
      expect(hexOf(eIfd),
          '72C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F2');
    });

    test('the MAC over E.IFD matches the published M.IFD', () {
      final s = Uint8List.fromList([...rndIfd, ...rndIc, ...kIfd]);
      final eIfd = desEde2Cbc(kEnc, s, encrypt: true);
      expect(hexOf(retailMac(kMac, pad(eIfd))), '5F1448EEA8AD90A7');
    });
  });
}
