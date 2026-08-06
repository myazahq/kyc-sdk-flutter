import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_pace_params.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_crypto.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_session.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_tlv.dart';

import 'emrtd_pace_chip.dart';

// ─── Which way into the chip, and in what order ───────────────────────────────
//
// A chip may accept BAC, PACE, or both. The ordering matters more than it looks:
// this SDK's BAC has read real passports for a long time and its PACE has read
// none, so BAC is tried first and PACE only when BAC is refused. In that order
// PACE can only ADD documents that can be read, never remove one that already
// worked.
//
// These tests pin that ordering down, because it is the kind of thing a later
// refactor silently inverts. Each states the order it is testing EXPLICITLY
// rather than inheriting `preferPaceAccess` — a test whose meaning changes with
// ambient config is not pinning anything.

const _arc = '04007F0007020204';
const _ecdhGmAes128 = '${_arc}0202';

/// Records which protocols were attempted, and can be told to refuse either.
class _Chip {
  final bool acceptsBac;
  final bool offersPace;
  final PaceChip? pace;

  bool triedBac = false;
  bool triedPace = false;
  bool selectedApplication = false;

  _Chip({required this.acceptsBac, required this.offersPace, this.pace});

  Future<Uint8List> transceive(Uint8List cmd) async {
    final ins = cmd[1];

    // SELECT — application, master file, or an elementary file.
    if (ins == 0xA4) {
      if (cmd[2] == 0x04) selectedApplication = true;
      if (cmd[2] == 0x02 && cmd.length >= 7 && cmd[5] == 0x01 && cmd[6] == 0x1C) {
        return offersPace ? hex('9000') : hex('6a82');
      }
      return hex('9000');
    }

    // Plain READ BINARY — only EF.CardAccess is read this way.
    if (ins == 0xB0 && cmd[0] == 0x00) {
      if (!offersPace) return hex('6a82');
      return Uint8List.fromList([..._cardAccessFile(), 0x90, 0x00]);
    }

    // BAC.
    if (ins == 0x84) {
      triedBac = true;
      if (!acceptsBac) return hex('6982');
      return Uint8List.fromList([..._rndIc, 0x90, 0x00]);
    }
    if (ins == 0x82) {
      triedBac = true;
      if (!acceptsBac) return hex('6300');
      return _mutualAuthenticate(cmd);
    }

    // PACE.
    if (ins == 0x22 || ins == 0x86) {
      triedPace = true;
      if (pace == null) return hex('6a80');
      return pace!.transceive(cmd);
    }

    return hex('6d00');
  }

  static final _rndIc = Uint8List.fromList(List.filled(8, 0x11));

  /// The chip's half of BAC: verify the terminal's cryptogram, then answer with
  /// its own key material so a real session opens.
  Uint8List _mutualAuthenticate(Uint8List cmd) {
    final seed = keySeed(
      documentNumber: 'L898902C',
      dateOfBirth: '690806',
      dateOfExpiry: '940623',
    );
    final kEnc = deriveKey(seed, 1);
    final kMac = deriveKey(seed, 2);

    final eIfd = Uint8List.sublistView(cmd, 5, 37);
    final mIfd = Uint8List.sublistView(cmd, 37, 45);
    if (!bytesEqual(retailMac(kMac, pad(eIfd)), mIfd)) return hex('6300');

    final s = desEde2Cbc(kEnc, eIfd, encrypt: false);
    final rndIfd = Uint8List.sublistView(s, 0, 8);
    final kIfd = Uint8List.sublistView(s, 16, 32);
    if (!bytesEqual(Uint8List.sublistView(s, 8, 16), _rndIc)) return hex('6300');

    final kIc = Uint8List.fromList(List.filled(16, 0x22));
    final r = Uint8List.fromList([..._rndIc, ...rndIfd, ...kIc]);
    final eIc = desEde2Cbc(kEnc, r, encrypt: true);
    final mIc = retailMac(kMac, pad(eIc));
    // Silence the unused warning on key material the chip legitimately ignores.
    assert(kIfd.length == 16);
    return Uint8List.fromList([...eIc, ...mIc, 0x90, 0x00]);
  }

  static Uint8List _cardAccessFile() => tlvOf(0x31, [
        tlvOf(0x30, [
          tlv(0x06, hex(_ecdhGmAes128)),
          tlv(0x02, Uint8List.fromList([2])),
          tlv(0x02, Uint8List.fromList([13])), // brainpoolP256r1
        ]),
      ]);
}

PaceChip _paceChip() {
  final protocol = paceProtocolFromOid(hex(_ecdhGmAes128))!;
  final curve = paceCurveForParameterId(13)!;
  return PaceChip(
    curve: curve,
    protocol: protocol,
    // The password key comes from the same MRZ the session derives from.
    passwordKey: protocol.suite.deriveKey(
      keySeed(
        documentNumber: 'L898902C',
        dateOfBirth: '690806',
        dateOfExpiry: '940623',
      ),
      3,
    ),
  );
}

void main() {
  group('choosing an access protocol', () {
    test('a chip that accepts BAC is never asked about PACE', () async {
      final chip = _Chip(acceptsBac: true, offersPace: true, pace: _paceChip());
      final session = EmrtdSession(chip.transceive, random: Random(1));

      await session.establishSession(
        documentNumber: 'L898902C',
        dateOfBirth: '690806',
        dateOfExpiry: '940623',
        preferPace: false,
      );

      expect(session.isOpen, isTrue);
      expect(session.accessProtocol, 'bac');
      expect(chip.triedBac, isTrue);
      expect(chip.triedPace, isFalse,
          reason: 'a working BAC must never be replaced by an unproven PACE');
      expect(chip.selectedApplication, isTrue,
          reason: 'BAC selects the application in the clear first');
    });

    test('a chip that refuses BAC is then tried with PACE', () async {
      final chip = _Chip(acceptsBac: false, offersPace: true, pace: _paceChip());
      final session = EmrtdSession(chip.transceive, random: Random(2));

      await session.establishSession(
        documentNumber: 'L898902C',
        dateOfBirth: '690806',
        dateOfExpiry: '940623',
        preferPace: false,
      );

      expect(chip.triedBac, isTrue, reason: 'BAC comes first');
      expect(chip.triedPace, isTrue, reason: 'and PACE is the fallback');
      expect(session.isOpen, isTrue);
      expect(session.accessProtocol, 'pace');
    });

    test('preferring PACE reverses the order', () async {
      final chip = _Chip(acceptsBac: false, offersPace: true, pace: _paceChip());
      final session = EmrtdSession(chip.transceive, random: Random(3));

      await session.establishSession(
        documentNumber: 'L898902C',
        dateOfBirth: '690806',
        dateOfExpiry: '940623',
        preferPace: true,
      );

      expect(chip.triedPace, isTrue);
      expect(chip.triedBac, isFalse, reason: 'PACE succeeded, so BAC was never needed');
      expect(session.accessProtocol, 'pace');
    });

    test('a chip offering no PACE reports the BAC failure', () async {
      final chip = _Chip(acceptsBac: false, offersPace: false);
      final session = EmrtdSession(chip.transceive, random: Random(4));

      await expectLater(
        session.establishSession(
          documentNumber: 'L898902C',
          dateOfBirth: '690806',
          dateOfExpiry: '940623',
          preferPace: false,
        ),
        throwsA(isA<EmrtdError>()),
      );
      expect(chip.triedPace, isFalse);
    });
  });
}
