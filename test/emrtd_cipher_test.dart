import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_cipher.dart';

// ─── AES cipher suite, against published vectors ──────────────────────────────
//
// PACE may negotiate AES instead of the 3DES that BAC always uses. The two
// primitives that carries in — AES-CBC and AES-CMAC — both have published test
// vectors independent of ICAO, so they can be checked outright rather than only
// for self-consistency: NIST SP 800-38A for CBC, RFC 4493 for CMAC.

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.replaceAll(' ', '').length; i += 2)
        int.parse(s.replaceAll(' ', '').substring(i, i + 2), radix: 16),
    ]);
String _hexOf(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final key = _hex('2b7e151628aed2a6abf7158809cf4f3c');

  group('AES-CMAC (RFC 4493)', () {
    // Our MAC is truncated to 8 bytes, as ICAO specifies, so each expected
    // value below is the leading half of the RFC's 16-byte answer.
    const suite = AesSuite(16);

    test('example 1 — empty message', () {
      expect(_hexOf(suite.mac(key, Uint8List(0))), 'bb1d6929e9593728');
    });

    test('example 2 — one block', () {
      final m = _hex('6bc1bee22e409f96e93d7e117393172a');
      expect(_hexOf(suite.mac(key, m)), '070a16b46b4d4144');
    });

    test('example 3 — a partial block', () {
      final m = _hex('6bc1bee22e409f96e93d7e117393172a'
          'ae2d8a571e03ac9c9eb76fac45af8e51'
          '30c81c46a35ce411');
      expect(_hexOf(suite.mac(key, m)), 'dfa66747de9ae630');
    });

    test('example 4 — four blocks', () {
      final m = _hex('6bc1bee22e409f96e93d7e117393172a'
          'ae2d8a571e03ac9c9eb76fac45af8e51'
          '30c81c46a35ce411e5fbc1191a0a52ef'
          'f69f2445df4f9b17ad2b417be66c3710');
      expect(_hexOf(suite.mac(key, m)), '51f0bebf7e3b9d92');
    });
  });

  group('AES-CBC (NIST SP 800-38A F.2)', () {
    const suite = AesSuite(16);

    test('encrypts with the IV the chip counter implies', () {
      // Feed the counter that encrypts to the standard's IV, so the published
      // ciphertext applies to our IV-derivation path rather than around it.
      final iv = _hex('000102030405060708090a0b0c0d0e0f');
      final ssc = _decryptBlock(key, iv);

      final plain = _hex('6bc1bee22e409f96e93d7e117393172a'
          'ae2d8a571e03ac9c9eb76fac45af8e51');
      final out = suite.encrypt(key, plain, ssc: ssc);
      expect(
        _hexOf(out),
        '7649abac8119b246cee98e9b12e9197d'
        '5086cb9b507219ee95db113a917678b2',
      );
      expect(suite.decrypt(key, out, ssc: ssc), plain);
    });

    test('the same plaintext under two counters gives different ciphertext',
        () {
      // This is the point of deriving the IV from the counter rather than
      // using a fixed one: repeated commands must not be recognisable.
      final plain = _hex('6bc1bee22e409f96e93d7e117393172a');
      final a = suite.encrypt(key, plain, ssc: Uint8List(16)..[15] = 1);
      final b = suite.encrypt(key, plain, ssc: Uint8List(16)..[15] = 2);
      expect(a, isNot(b));
    });
  });

  group('key derivation', () {
    // ICAO 9303 §9.7.1: SHA-1 for 3DES and AES-128, SHA-256 above that, and
    // the parity adjustment is a DES convention that AES keys must not get.
    test('produces the right key length for each suite', () {
      final secret = _hex('0011223344556677');
      expect(const DesEde2Suite().deriveKey(secret, 1).length, 16);
      expect(const AesSuite(16).deriveKey(secret, 1).length, 16);
      expect(const AesSuite(24).deriveKey(secret, 1).length, 24);
      expect(const AesSuite(32).deriveKey(secret, 1).length, 32);
    });

    test('AES-128 skips the DES parity adjustment', () {
      // Same digest underneath, so any difference is exactly the parity bits —
      // applying them to an AES key would be a silent wrong-key bug.
      final secret = _hex('0011223344556677');
      final des = const DesEde2Suite().deriveKey(secret, 1);
      final aes = const AesSuite(16).deriveKey(secret, 1);
      expect(aes, isNot(des));
      for (var i = 0; i < 16; i++) {
        expect(des[i] & 0xFE, aes[i] & 0xFE, reason: 'byte $i differs beyond parity');
      }
    });

    test('the encryption and MAC keys differ', () {
      final secret = _hex('0011223344556677');
      const suite = AesSuite(16);
      expect(suite.deriveKey(secret, 1), isNot(suite.deriveKey(secret, 2)));
    });
  });
}

/// Inverse of the suite's IV derivation, so a published IV can be turned into
/// the counter value that produces it.
Uint8List _decryptBlock(Uint8List key, Uint8List block) {
  final engine = pc.AESEngine()..init(false, pc.KeyParameter(key));
  final out = Uint8List(16);
  engine.processBlock(block, 0, out, 0);
  return out;
}
