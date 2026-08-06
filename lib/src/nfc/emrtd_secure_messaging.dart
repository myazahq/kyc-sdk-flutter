import 'dart:typed_data';

import 'emrtd_cipher.dart';
import 'emrtd_crypto.dart';
import 'emrtd_sm_objects.dart';

// ─── Secure Messaging (ICAO 9303 Part 11, §9.8) ───────────────────────────────
//
// Once BAC succeeds, EVERY command to the chip is encrypted and authenticated
// with the session keys, and every response comes back the same way. This is
// that envelope.
//
// The send-sequence counter is the part worth understanding: it increments
// before the command and again before the response, and it is folded into each
// MAC. If it ever drifts, the chip rejects everything from that point on — so
// it lives here, in one place, rather than being tracked by callers.

/// Thrown when a response fails its MAC check or is malformed. Treated as a
/// read failure: a chip whose replies we cannot authenticate is one we cannot
/// trust, and the SDK falls back to the document photo.
class SecureMessagingError implements Exception {
  final String message;
  const SecureMessagingError(this.message);
  @override
  String toString() => 'SecureMessagingError: $message';
}

/// A response's plain data and the chip's processing status.
///
/// The status is the one the chip reports inside DO'99', NOT the status word on
/// the outside of the response. They usually agree, but when they don't the
/// inner one is the truth: secure messaging itself can succeed (outer 0x9000)
/// while the command it carried returned a warning like "end of file reached
/// before Le bytes". Reading the outer word would make a truncated read look
/// complete.
typedef SmResponse = ({Uint8List data, int sw});

class SecureMessaging {
  final Uint8List ksEnc;
  final Uint8List ksMac;

  /// Which cipher the session runs on. BAC is always 3DES; a PACE session may
  /// have negotiated AES, which changes the block size, the padding unit, the
  /// counter width and how the IV is derived.
  final CipherSuite suite;

  /// Send-sequence counter, one cipher block wide.
  final Uint8List _ssc;

  SecureMessaging({
    required this.ksEnc,
    required this.ksMac,
    required Uint8List ssc,
    this.suite = bacCipherSuite,
  }) : _ssc = Uint8List.fromList(ssc);

  Uint8List get ssc => Uint8List.fromList(_ssc);

  void _incrementSsc() {
    for (var i = _ssc.length - 1; i >= 0; i--) {
      if (_ssc[i] == 0xFF) {
        _ssc[i] = 0;
      } else {
        _ssc[i]++;
        return;
      }
    }
  }

  /// Wraps a plain command APDU for transmission.
  ///
  /// [header] is CLA/INS/P1/P2 (4 bytes, CLA already flagged 0x0C by the
  /// caller's construction below), [data] the command body, [le] the expected
  /// response length (null when none is requested).
  ///
  /// [dataTag] selects the data object the body is carried in: DO'87' for
  /// ordinary commands, DO'85' for extended READ BINARY, which by definition
  /// carries no padding-content indicator.
  Uint8List protect(
    Uint8List header, {
    Uint8List? data,
    int? le,
    int dataTag = 0x87,
  }) {
    _incrementSsc();

    final body = BytesBuilder();

    // DO'87'/DO'85' — the encrypted command data. DO'87' is prefixed 0x01 to
    // mark it as padding-content per ISO 7816-4; DO'85' is not.
    if (data != null && data.isNotEmpty) {
      final enc = suite.encrypt(ksEnc, suite.padTo(data), ssc: _ssc);
      final indicator = dataTag == 0x87;
      body
        ..addByte(dataTag)
        ..add(berLengthBytes(enc.length + (indicator ? 1 : 0)));
      if (indicator) body.addByte(0x01);
      body.add(enc);
    }

    // DO'97' — the expected length.
    if (le != null) {
      body
        ..addByte(0x97)
        ..addByte(0x01)
        ..addByte(le & 0xFF);
    }

    // The MAC covers SSC || padded header || the data objects above.
    final maskedHeader = Uint8List.fromList(header)..[0] = header[0] | 0x0C;
    final macInput = BytesBuilder()
      ..add(_ssc)
      ..add(suite.padTo(maskedHeader))
      ..add(body.toBytes());
    final mac = suite.mac(ksMac, suite.padTo(macInput.toBytes()));

    final protectedData = BytesBuilder()
      ..add(body.toBytes())
      ..addByte(0x8E)
      ..addByte(0x08)
      ..add(mac);

    final payload = protectedData.toBytes();
    return Uint8List.fromList([
      ...maskedHeader,
      payload.length,
      ...payload,
      0x00, // Le — the response is itself a wrapped object.
    ]);
  }

  /// Unwraps a response APDU, verifying its MAC and returning the plain data
  /// together with the chip's own status word.
  ///
  /// A non-success status is NOT an error here: several statuses carry valid
  /// data alongside a warning, and the caller decides what to do about them.
  /// Only a failed MAC or a malformed envelope throws — a reply we cannot
  /// authenticate is one we cannot use.
  SmResponse unwrap(Uint8List response) {
    if (response.length < 2) {
      throw const SecureMessagingError('response too short');
    }

    final outerSw = (response[response.length - 2] << 8) |
        response[response.length - 1];
    final body = response.sublist(0, response.length - 2);

    // A bare status word — the chip refused before secure messaging applied
    // (e.g. 0x6987/0x6988). There is nothing to authenticate, and critically
    // the send-sequence counter must NOT advance: it only steps for messages
    // that actually crossed the secure channel.
    if (body.isEmpty) return (data: Uint8List(0), sw: outerSw);

    _incrementSsc();

    final ResponseObjects parts;
    try {
      parts = splitResponseObjects(body);
    } on ResponseObjectsError catch (e) {
      throw SecureMessagingError(e.message);
    }
    final encrypted = parts.encrypted;
    final mac = parts.mac;

    if (mac == null) {
      throw const SecureMessagingError('response carried no MAC');
    }

    final expected = suite.mac(
      ksMac,
      suite.padTo(Uint8List.fromList([..._ssc, ...parts.macCovered])),
    );
    if (!_constantTimeEquals(expected, mac)) {
      throw const SecureMessagingError('response MAC mismatch');
    }

    final data = encrypted == null
        ? Uint8List(0)
        : unpadFromBlock(
            suite.decrypt(ksEnc, encrypted, ssc: _ssc),
            suite.blockSize,
          );
    return (data: data, sw: parts.statusWord ?? outerSw);
  }

  /// Unwraps a response and insists it succeeded. For commands where anything
  /// other than success is fatal — SELECT, above all.
  Uint8List unprotect(Uint8List response) {
    final r = unwrap(response);
    if (r.sw != 0x9000) {
      throw SecureMessagingError(
        'chip returned ${r.sw.toRadixString(16).padLeft(4, '0')}',
      );
    }
    return r.data;
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

}
