import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_crypto.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_session.dart';

// ─── Reading files off chips that misbehave ───────────────────────────────────
//
// The BAC handshake is fully specified and can be checked against the standard's
// worked example. Reading files is where documents actually differ: how many
// bytes a chip will serve per READ BINARY is not discoverable except by asking,
// and chips disagree about how to say no. Some refuse with an error, some name
// their limit, some hand back a short read with a warning.
//
// These tests drive the reader against a chip that does each of those things,
// and assert it still comes away with the whole file. The fake chip below speaks
// real secure messaging — it verifies the MACs it receives and signs the ones it
// sends — so a reader that got the envelope or the send-sequence counter wrong
// would fail here rather than passing on a mock.

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

// The published ICAO 9303 D.3 values, so the session opens with keys both sides
// of this test agree on without inventing any crypto.
final _rndIc = _hex('4608F91988702212');
final _rndIfd = _hex('781723860C06C226');
final _kIfd = _hex('0B795240CB7049B01C19B33E32804F0B');
final _authResponse = _hex(
  '46B9342A41396CD7386BF5803104D7CEDC122B9132139BAF2EEDC94EE178534F'
  '2F2D235D074D74499000',
);
final _ksEnc = _hex('979EC13B1CBFE9DCD01AB0FED307EAE5');
final _ksMac = _hex('F1CB1F1FB5ADF208806B89DC579DC1F8');
final _initialSsc = _hex('887022120C06C226');

/// How the fake chip answers a read it considers too long.
enum RefusalStyle {
  /// 0x6700 — "wrong length", nothing returned.
  wrongLength,

  /// 0x6C xx — "wrong length, here is the exact one I will serve".
  exactLength,

  /// 0x6282 — a short read with an end-of-file warning attached.
  shortRead,
}

class _FakeChip {
  final Uint8List file;
  final int cap;
  final RefusalStyle style;

  /// Status the chip reports inside DO'99' for reads, overriding success.
  final int? forcedReadStatus;

  final Uint8List _ssc = Uint8List.fromList(_initialSsc);
  int reads = 0;
  int refusals = 0;
  final servedLengths = <int>[];

  _FakeChip(
    this.file, {
    this.cap = 1 << 30,
    this.style = RefusalStyle.wrongLength,
    this.forcedReadStatus,
  });

  void _inc() {
    for (var i = _ssc.length - 1; i >= 0; i--) {
      if (_ssc[i] == 0xFF) {
        _ssc[i] = 0;
      } else {
        _ssc[i]++;
        return;
      }
    }
  }

  Future<Uint8List> transceive(Uint8List cmd) async {
    // Pre-session commands travel in the clear.
    if (cmd[1] == 0x84) return Uint8List.fromList([..._rndIc, 0x90, 0x00]);
    if (cmd[1] == 0x82) return _authResponse;
    if (cmd[0] == 0x00 && cmd[1] == 0xA4) {
      return Uint8List.fromList([0x90, 0x00]);
    }

    _inc(); // the command's SSC step
    _verifyCommandMac(cmd);

    if (cmd[1] == 0xA4) return _respond(sw: 0x9000); // SELECT under SM
    if (cmd[1] == 0xB0) return _readBinary(cmd);
    if (cmd[1] == 0xB1) return _readBinaryExtended(cmd);
    return _respond(sw: 0x6D00);
  }

  /// A reader that mis-built the envelope or drifted the counter fails here.
  void _verifyCommandMac(Uint8List cmd) {
    final lc = cmd[4];
    final body = Uint8List.sublistView(cmd, 5, 5 + lc);
    final macStart = body.length - 10; // DO'8E' is 8E 08 <8 bytes>
    expect(body[macStart], 0x8E, reason: 'command carried no MAC');
    final mac = Uint8List.sublistView(body, macStart + 2);
    final covered = Uint8List.sublistView(body, 0, macStart);
    final header = Uint8List.fromList(cmd.sublist(0, 4));
    final expected = retailMac(
      _ksMac,
      pad(Uint8List.fromList([..._ssc, ...pad(header), ...covered])),
    );
    expect(mac, expected, reason: 'command MAC did not verify');
  }

  Uint8List _readBinary(Uint8List cmd) {
    final offset = ((cmd[2] & 0x7F) << 8) | cmd[3];
    final want = _requestedLe(cmd);
    return _serve(offset, want);
  }

  Uint8List _readBinaryExtended(Uint8List cmd) {
    // The offset arrives encrypted in DO'85' as TLV 54 04 <offset>.
    final body = _commandData(cmd);
    expect(body[0], 0x54);
    final offset = (body[2] << 24) | (body[3] << 16) | (body[4] << 8) | body[5];
    final want = _requestedLe(cmd) - 3; // caller left room for the 0x53 wrapper
    final served = _clamp(offset, want);
    if (served == null) return _refuse(want);
    reads++;
    servedLengths.add(served.length);
    // Extended reads come back wrapped in tag 0x53.
    final wrapped = BytesBuilder()
      ..addByte(0x53)
      ..add(served.length < 0x80
          ? [served.length]
          : [0x81, served.length])
      ..add(served);
    return _respond(data: wrapped.toBytes(), sw: 0x9000);
  }

  Uint8List _serve(int offset, int want) {
    final served = _clamp(offset, want);
    if (served == null) return _refuse(want);
    reads++;
    servedLengths.add(served.length);
    if (forcedReadStatus != null) {
      return _respond(data: served, sw: forcedReadStatus!);
    }
    // A short read because the file ended is a plain success, not a warning.
    return _respond(data: served, sw: 0x9000);
  }

  /// Returns the bytes the chip is willing to serve, or null if it refuses.
  Uint8List? _clamp(int offset, int want) {
    if (want > cap) {
      if (style != RefusalStyle.shortRead) return null;
      want = cap; // hands back less than asked, with a warning
    }
    final end = (offset + want) > file.length ? file.length : offset + want;
    if (offset >= file.length) return Uint8List(0);
    return Uint8List.sublistView(file, offset, end);
  }

  Uint8List _refuse(int want) {
    refusals++;
    return switch (style) {
      RefusalStyle.wrongLength => _respond(sw: 0x6700),
      RefusalStyle.exactLength => _respond(sw: 0x6C00 | cap),
      RefusalStyle.shortRead => _respond(sw: 0x9000),
    };
  }

  Uint8List _respond({Uint8List? data, required int sw}) {
    _inc(); // the response's SSC step
    final body = BytesBuilder();
    if (data != null && data.isNotEmpty) {
      final enc = desEde2Cbc(_ksEnc, pad(data), encrypt: true);
      final len = enc.length + 1;
      body
        ..addByte(0x87)
        ..add(len < 0x80 ? [len] : [0x81, len])
        ..addByte(0x01)
        ..add(enc);
    }
    // The status the chip really means, inside the authenticated envelope. The
    // outer word below stays 0x9000: secure messaging itself succeeded.
    body
      ..addByte(0x99)
      ..addByte(0x02)
      ..addByte((sw >> 8) & 0xFF)
      ..addByte(sw & 0xFF);

    final covered = body.toBytes();
    final mac = retailMac(
      _ksMac,
      pad(Uint8List.fromList([..._ssc, ...covered])),
    );
    return Uint8List.fromList([
      ...covered,
      0x8E, 0x08, ...mac, //
      0x90, 0x00,
    ]);
  }

  int _requestedLe(Uint8List cmd) {
    final lc = cmd[4];
    final body = Uint8List.sublistView(cmd, 5, 5 + lc);
    var i = 0;
    while (i < body.length) {
      final tag = body[i];
      var len = body[i + 1];
      var headerLen = 2;
      if (len == 0x81) {
        len = body[i + 2];
        headerLen = 3;
      }
      if (tag == 0x97) {
        final v = body[i + headerLen];
        return v == 0 ? 256 : v;
      }
      i += headerLen + len;
    }
    fail('command carried no expected-length object');
  }

  Uint8List _commandData(Uint8List cmd) {
    final lc = cmd[4];
    final body = Uint8List.sublistView(cmd, 5, 5 + lc);
    var i = 0;
    while (i < body.length) {
      final tag = body[i];
      var len = body[i + 1];
      var headerLen = 2;
      if (len == 0x81) {
        len = body[i + 2];
        headerLen = 3;
      }
      if (tag == 0x85 || tag == 0x87) {
        var value = Uint8List.sublistView(body, i + headerLen, i + headerLen + len);
        if (tag == 0x87) value = Uint8List.sublistView(value, 1);
        return unpad(desEde2Cbc(_ksEnc, value, encrypt: false));
      }
      i += headerLen + len;
    }
    fail('command carried no data object');
  }
}

/// A file with a BER-TLV header of [payload] bytes, filled with a recognisable
/// pattern so a misplaced chunk shows up as a mismatch rather than a length.
///
/// The period is 251 — prime, and deliberately so. An earlier version filled the
/// file with `i & 0xFF`, and the 32 KB test passed even with extended reads
/// disabled: reading past the 15-bit offset limit shifts every read by exactly
/// 32768, which is a multiple of 256, so the wrong bytes were byte-for-byte
/// identical to the right ones. A period that divides the bug is a test that
/// cannot see it.
Uint8List _file(int payload) {
  final head = payload < 0x80
      ? [0x61, payload]
      : payload <= 0xFF
          ? [0x61, 0x81, payload]
          : [0x61, 0x82, (payload >> 8) & 0xFF, payload & 0xFF];
  return Uint8List.fromList([
    ...head,
    for (var i = 0; i < payload; i++) i % 251,
  ]);
}

Future<EmrtdSession> _openSession(_FakeChip chip) async {
  final session = EmrtdSession(chip.transceive);
  await session.openSession(
    documentNumber: 'L898902C',
    dateOfBirth: '690806',
    dateOfExpiry: '940623',
    nonce: _rndIfd,
    keyMaterial: _kIfd,
  );
  return session;
}

void main() {
  group('reading a file', () {
    test('reads a whole multi-chunk file from a cooperative chip', () async {
      final file = _file(500);
      final chip = _FakeChip(file);
      final session = await _openSession(chip);

      expect(await session.readFile(EfId.dg1), file);
      expect(chip.refusals, 0);
    });

    test('reads a file that fits in the first look-ahead', () async {
      final file = _file(4); // 6 bytes total, under the 8-byte head read
      final chip = _FakeChip(file);
      final session = await _openSession(chip);

      expect(await session.readFile(EfId.dg1), file);
      expect(chip.reads, 1, reason: 'no follow-up read was needed');
    });
  });

  group('chips that will not serve a full-length read', () {
    test('backs off when the chip refuses with a wrong-length error', () async {
      final file = _file(600);
      final chip = _FakeChip(file, cap: 64);
      final session = await _openSession(chip);

      expect(await session.readFile(EfId.dg1), file);
      // It had to discover the limit, and then stay under it.
      expect(chip.refusals, greaterThan(0));
      expect(session.maxRead, lessThanOrEqualTo(64));
      expect(chip.servedLengths.every((n) => n <= 64), isTrue);
    });

    test('adopts the exact length a chip names in 0x6Cxx', () async {
      final file = _file(400);
      final chip = _FakeChip(file, cap: 50, style: RefusalStyle.exactLength);
      final session = await _openSession(chip);

      expect(await session.readFile(EfId.dg1), file);
      expect(session.maxRead, 50, reason: 'the chip named its own limit');
      // One refusal is enough when the chip tells you the answer.
      expect(chip.refusals, 1);
    });

    test('keeps the data from a short read and asks for less next time',
        () async {
      final file = _file(600);
      final chip = _FakeChip(file, cap: 80, style: RefusalStyle.shortRead);
      final session = await _openSession(chip);

      expect(await session.readFile(EfId.dg1), file);
      expect(chip.servedLengths.every((n) => n <= 80), isTrue);
    });

    test('gives up rather than looping when no read length works', () async {
      final chip = _FakeChip(_file(600), cap: 0);
      final session = await _openSession(chip);

      await expectLater(
        session.readFile(EfId.dg1),
        throwsA(isA<EmrtdError>()
            .having((e) => e.code, 'code', 'read_failed')),
      );
    });
  });

  test('a file past the 32 KB offset switches to extended reads', () async {
    // Large enough that the ordinary 15-bit offset runs out partway through —
    // a high-resolution portrait really can get here.
    final file = _file(40000);
    final chip = _FakeChip(file);
    final session = await _openSession(chip);

    expect(await session.readFile(EfId.dg2), file);
  });

  test('an error reported inside DO\'99\' is not read as success', () async {
    // The chip wraps a failure in a perfectly valid secure-messaging envelope:
    // the outer status word is 0x9000 because secure messaging worked, and the
    // real answer is inside. Trusting the outer word would silently return a
    // truncated file.
    final chip = _FakeChip(_file(400), forcedReadStatus: 0x6A82);
    final session = await _openSession(chip);

    await expectLater(
      session.readFile(EfId.sod),
      throwsA(isA<EmrtdError>().having((e) => e.code, 'code', 'read_failed')),
    );
  });
}
