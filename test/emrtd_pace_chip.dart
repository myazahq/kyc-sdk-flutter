import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_cipher.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_pace_params.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_tlv.dart';

// A chip that performs the chip's half of PACE-GM properly: a real encrypted
// nonce, its own mapping and key agreement, independently derived session keys,
// and a genuine check of the terminal's authentication token. Shared so the
// handshake tests and the protocol-ordering tests drive the same thing.

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

/// The chip side of PACE-GM.
class PaceChip {
  final pc.ECDomainParameters curve;
  final PaceProtocol protocol;
  final Uint8List passwordKey;
  final Random rng;

  /// Set when the chip decides the terminal proved the same keys.
  bool authenticated = false;
  Uint8List? ksEnc;
  Uint8List? ksMac;

  /// Recorded so a test can assert the terminal announced the right protocol.
  Uint8List? announcedOid;
  int? announcedKeyReference;

  late Uint8List nonce;
  late BigInt mapPrivate;
  late pc.ECPoint sessionPublic;
  late BigInt sessionPrivate;
  late pc.ECPoint mappedGenerator;

  PaceChip({
    required this.curve,
    required this.protocol,
    required this.passwordKey,
    Random? rng,
  }) : rng = rng ?? Random(7);

  CipherSuite get suite => protocol.suite;

  Future<Uint8List> transceive(Uint8List cmd) async {
    final lc = cmd[4];
    final body = Uint8List.sublistView(cmd, 5, 5 + lc);

    if (cmd[1] == 0x22) return setAt(body);
    if (cmd[1] == 0x86) return generalAuthenticate(cmd[0], body);
    return hex('6d00');
  }

  Uint8List setAt(Uint8List body) {
    announcedOid = findTlv(body, 0x80)?.value;
    announcedKeyReference = findTlv(body, 0x83)?.value.first;
    return hex('9000');
  }

  Uint8List generalAuthenticate(int cla, Uint8List body) {
    final template = parseTlv(body);
    if (template.tag != 0x7C) return hex('6a80');
    final inner = template.value;

    // Step 1 — a fresh nonce, encrypted under the password key.
    if (inner.isEmpty) {
      nonce = randomBytes(suite.blockSize);
      final encrypted = suite.encrypt(passwordKey, nonce);
      return reply(0x80, encrypted);
    }

    final mapping = findTlv(inner, 0x81);
    if (mapping != null) {
      // Step 2 — contribute a mapping key and build the same fresh generator.
      mapPrivate = scalar();
      final ours = (curve.G * mapPrivate)!;
      final theirs = curve.curve.decodePoint(mapping.value)!;
      final shared = (theirs * mapPrivate)!;
      mappedGenerator = ((curve.G * toBigInt(nonce))! + shared)!;
      return reply(0x82, ours.getEncoded(false));
    }

    final agreement = findTlv(inner, 0x83);
    if (agreement != null) {
      // Step 3 — key agreement over the mapped generator.
      sessionPrivate = scalar();
      sessionPublic = (mappedGenerator * sessionPrivate)!;
      final theirs = curve.curve.decodePoint(agreement.value)!;
      final agreed = (theirs * sessionPrivate)!;
      final secret = fieldBytes(agreed.x!.toBigInteger()!);
      ksEnc = suite.deriveKey(secret, 1);
      ksMac = suite.deriveKey(secret, 2);
      terminalSessionPublic = theirs;
      return reply(0x84, sessionPublic.getEncoded(false));
    }

    final token = findTlv(inner, 0x85);
    if (token != null) {
      // Step 4 — the terminal must have MACed OUR public key with the same
      // MAC key, or it did not arrive at the same secret.
      final expected =
          suite.token(ksMac!, tokenInput(protocol.oid, sessionPublic));
      if (!bytesEqual(token.value, expected)) return hex('6300');
      authenticated = true;
      final ours =
          suite.token(ksMac!, tokenInput(protocol.oid, terminalSessionPublic));
      return reply(0x86, ours);
    }

    return hex('6a80');
  }

  late pc.ECPoint terminalSessionPublic;

  Uint8List reply(int tag, Uint8List value) => Uint8List.fromList([
        ...tlvOf(0x7C, [tlv(tag, value)]),
        0x90, 0x00,
      ]);

  BigInt scalar() {
    while (true) {
      final n = toBigInt(randomBytes((curve.n.bitLength + 7) ~/ 8));
      if (n > BigInt.zero && n < curve.n) return n;
    }
  }

  Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  Uint8List fieldBytes(BigInt value) {
    final width = (curve.curve.fieldSize + 7) ~/ 8;
    final out = Uint8List(width);
    var v = value;
    for (var i = width - 1; i >= 0 && v > BigInt.zero; i--) {
      out[i] = (v & BigInt.from(0xFF)).toInt();
      v = v >> 8;
    }
    return out;
  }
}

Uint8List tokenInput(Uint8List oid, pc.ECPoint point) => tlvOf(0x7F49, [
      tlv(0x06, oid),
      tlv(0x86, point.getEncoded(false)),
    ]);

BigInt toBigInt(Uint8List bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  return n;
}

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

