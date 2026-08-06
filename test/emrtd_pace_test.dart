import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_card_access.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_cipher.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_pace.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_pace_params.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_tlv.dart';

import 'emrtd_pace_chip.dart';

// ─── PACE, against a chip that runs the other half ────────────────────────────
//
// Unlike BAC, PACE has no worked example in the standard that can be replayed
// here, so these tests instead stand up a chip that performs the chip's side of
// the protocol properly: it issues a real encrypted nonce, does its own mapping
// and key agreement, derives session keys independently, and checks the
// terminal's authentication token before answering with its own.
//
// What that does prove: the mapping arithmetic, the data-object encodings, the
// command chaining, the token construction and the session-key derivation all
// agree between two parties, and that the secured channel opened afterwards
// actually carries a message. What it cannot prove is that both sides read the
// standard the same wrong way — for that, only a real passport will do. The
// primitives underneath (AES-CBC, CMAC) are pinned to published vectors
// separately, in emrtd_cipher_test.dart.

/// A PACEInfo the way EF.CardAccess carries it: a SET of SEQUENCEs, each an
/// OID plus a version and optionally a domain-parameter id.
Uint8List _cardAccess(List<(String oid, int version, int? params)> infos) {
  final seqs = <Uint8List>[];
  for (final (oid, version, params) in infos) {
    final fields = <Uint8List>[
      tlv(0x06, hex(oid)),
      tlv(0x02, Uint8List.fromList([version])),
      if (params != null) tlv(0x02, Uint8List.fromList([params])),
    ];
    seqs.add(tlvOf(0x30, fields));
  }
  return tlvOf(0x31, seqs);
}

// The PACE arc 0.4.0.127.0.7.2.2.4, then two bytes: the mapping/key-agreement
// branch, then the cipher suite.
const _arc = '04007F0007020204';
const _ecdhGmAes128 = '${_arc}0202'; // 0.4.0.127.0.7.2.2.4.2.2
const _ecdhGmAes256 = '${_arc}0204'; // 0.4.0.127.0.7.2.2.4.2.4
const _dhGm3des = '${_arc}0101';     // 0.4.0.127.0.7.2.2.4.1.1
const _ecdhImAes128 = '${_arc}0402'; // 0.4.0.127.0.7.2.2.4.4.2 — integrated

void main() {
  group('protocol identifiers', () {
    test('decodes the ECDH generic-mapping AES-128 identifier', () {
      final p = paceProtocolFromOid(hex(_ecdhGmAes128))!;
      expect(p.keyAgreement, PaceKeyAgreement.ecdh);
      expect(p.mapping, PaceMapping.generic);
      expect(p.suite.algorithm, CipherAlgorithm.aes);
      expect(p.suite.keyLength, 16);
      expect(p.isSupported, isTrue);
    });

    test('decodes 3DES and the longer AES keys', () {
      expect(paceProtocolFromOid(hex(_dhGm3des))!.suite.keyLength, 16);
      expect(paceProtocolFromOid(hex(_dhGm3des))!.suite.algorithm,
          CipherAlgorithm.desEde2);
      expect(paceProtocolFromOid(hex(_ecdhGmAes256))!.suite.keyLength, 32);
    });

    test('marks the variants this build cannot run as unsupported', () {
      // Finite-field DH and integrated mapping both fall back to BAC rather
      // than failing a read.
      final dh = paceProtocolFromOid(hex(_dhGm3des))!;
      expect(dh.keyAgreement, PaceKeyAgreement.dh);
      expect(dh.isSupported, isFalse);

      final im = paceProtocolFromOid(hex(_ecdhImAes128))!;
      expect(im.mapping, PaceMapping.integrated);
      expect(im.isSupported, isFalse);
    });

    test('ignores an identifier that is not PACE at all', () {
      expect(paceProtocolFromOid(hex('2A864886F70D010101')), isNull);
    });
  });

  group('EF.CardAccess', () {
    test('picks the strongest supported offering', () {
      final file = _cardAccess([
        (_ecdhGmAes128, 2, 13),
        (_ecdhGmAes256, 2, 13),
      ]);
      final offer = selectPaceOffer(parseCardAccess(file))!;
      expect(offer.protocol.suite.keyLength, 32);
      expect(offer.parameterId, 13);
    });

    test('skips offerings this build cannot run', () {
      final file = _cardAccess([(_dhGm3des, 2, 0)]);
      final offers = parseCardAccess(file);
      expect(offers, hasLength(1));
      expect(selectPaceOffer(offers), isNull);
      expect(paceGapFor(offers), PaceUnsupported.keyAgreement);
    });

    test('a chip offering no PACE yields nothing rather than an error', () {
      expect(parseCardAccess(Uint8List(0)), isEmpty);
      expect(selectPaceOffer(const []), isNull);
    });

    test('an unparseable file is treated as no PACE, not a failure', () {
      expect(parseCardAccess(hex('deadbeef')), isEmpty);
    });

    test('an unknown curve id is not selected', () {
      final file = _cardAccess([(_ecdhGmAes128, 2, 99)]);
      expect(selectPaceOffer(parseCardAccess(file)), isNull);
    });
  });

  group('PACE-GM handshake', () {
    for (final (label, oid) in [
      ('AES-128', _ecdhGmAes128),
      ('AES-256', _ecdhGmAes256),
    ]) {
      test('$label — both sides derive the same session keys', () async {
        final protocol = paceProtocolFromOid(hex(oid))!;
        final curve = paceCurveForParameterId(13)!; // brainpoolP256r1
        final passwordKey =
            protocol.suite.deriveKey(hex('0011223344556677'), 3);

        final chip = PaceChip(
          curve: curve,
          protocol: protocol,
          passwordKey: passwordKey,
        );

        final session = await runPaceEcdhGm(
          transceive: chip.transceive,
          protocol: protocol,
          curve: curve,
          passwordKey: passwordKey,
          random: Random(11),
        );

        expect(chip.authenticated, isTrue,
            reason: 'the chip accepted our authentication token');
        expect(session.ksEnc, chip.ksEnc);
        expect(session.ksMac, chip.ksMac);
        expect(session.ssc, Uint8List(protocol.suite.blockSize),
            reason: 'a PACE session starts its counter at zero');

        // The announced protocol and password reference reached the chip.
        expect(chip.announcedOid, hex(oid));
        expect(chip.announcedKeyReference, 1, reason: 'MRZ');
      });
    }

    test('the secured channel carries a command both sides agree on', () async {
      final protocol = paceProtocolFromOid(hex(_ecdhGmAes128))!;
      final curve = paceCurveForParameterId(12)!; // NIST P-256
      final passwordKey = protocol.suite.deriveKey(hex('a1b2c3d4'), 3);
      final chip = PaceChip(
        curve: curve,
        protocol: protocol,
        passwordKey: passwordKey,
      );

      final terminal = await runPaceEcdhGm(
        transceive: chip.transceive,
        protocol: protocol,
        curve: curve,
        passwordKey: passwordKey,
        random: Random(3),
      );

      // Wrap a SELECT on the terminal, unwrap it with the chip's keys. Any
      // disagreement about the AES envelope — block size, derived IV, counter
      // width — shows up as a MAC failure here.
      final chipSide = _mirror(chip);
      final apdu = terminal.protect(
        Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C]),
        data: hex('0101'),
      );
      expect(() => chipSide.verifyCommand(apdu), returnsNormally);
    });

    test('a wrong password fails as auth_failed, not a generic error',
        () async {
      final protocol = paceProtocolFromOid(hex(_ecdhGmAes128))!;
      final curve = paceCurveForParameterId(13)!;
      final chip = PaceChip(
        curve: curve,
        protocol: protocol,
        passwordKey: protocol.suite.deriveKey(hex('0011223344556677'), 3),
      );

      await expectLater(
        runPaceEcdhGm(
          transceive: chip.transceive,
          protocol: protocol,
          curve: curve,
          // A different MRZ produces a different password key, so the nonce
          // decrypts to noise and the tokens cannot agree.
          passwordKey: protocol.suite.deriveKey(hex('ffffffffffffffff'), 3),
          random: Random(5),
        ),
        throwsA(isA<PaceError>().having((e) => e.code, 'code', 'auth_failed')),
      );
      expect(chip.authenticated, isFalse);
    });

    test('a chip that echoes our own key is refused', () async {
      final protocol = paceProtocolFromOid(hex(_ecdhGmAes128))!;
      final curve = paceCurveForParameterId(13)!;
      final passwordKey = protocol.suite.deriveKey(hex('0011223344556677'), 3);
      final chip = _EchoChip(
        curve: curve,
        protocol: protocol,
        passwordKey: passwordKey,
      );

      await expectLater(
        runPaceEcdhGm(
          transceive: chip.transceive,
          protocol: protocol,
          curve: curve,
          passwordKey: passwordKey,
          random: Random(9),
        ),
        throwsA(isA<PaceError>()),
      );
    });
  });
}

/// Rebuilds the chip's view of the session so a terminal-side command can be
/// checked from the other end.
_MirrorSession _mirror(PaceChip chip) => _MirrorSession(
      ksEnc: chip.ksEnc!,
      ksMac: chip.ksMac!,
      suite: chip.suite,
    );

class _MirrorSession {
  final Uint8List ksEnc;
  final Uint8List ksMac;
  final CipherSuite suite;
  _MirrorSession({
    required this.ksEnc,
    required this.ksMac,
    required this.suite,
  });

  /// Recomputes the command MAC the way a chip would and insists it matches.
  void verifyCommand(Uint8List apdu) {
    final lc = apdu[4];
    final body = Uint8List.sublistView(apdu, 5, 5 + lc);
    final macStart = body.length - 10;
    final mac = Uint8List.sublistView(body, macStart + 2);
    final covered = Uint8List.sublistView(body, 0, macStart);
    final header = Uint8List.fromList(apdu.sublist(0, 4));

    // The counter stepped once for this command.
    final ssc = Uint8List(suite.blockSize)..[suite.blockSize - 1] = 1;
    final expected = suite.mac(
      ksMac,
      suite.padTo(Uint8List.fromList(
          [...ssc, ...suite.padTo(header), ...covered])),
    );
    if (!bytesEqual(mac, expected)) {
      throw StateError('the chip could not authenticate the command');
    }
  }
}

/// A chip that returns the terminal's own public key back at step 3.
class _EchoChip extends PaceChip {
  _EchoChip({
    required super.curve,
    required super.protocol,
    required super.passwordKey,
  });

  @override
  Uint8List generalAuthenticate(int cla, Uint8List body) {
    final template = parseTlv(body);
    final agreement = findTlv(template.value, 0x83);
    if (agreement != null) return reply(0x84, agreement.value);
    return super.generalAuthenticate(cla, body);
  }
}
