import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart' as pc;

import 'emrtd_cmac.dart';
import 'emrtd_crypto.dart' as crypto;

// ─── Cipher suites (ICAO 9303 Part 11, §9.7 and §9.8) ─────────────────────────
//
// A chip session is secured with one of two cipher suites. BAC always uses
// two-key 3DES with the ISO 9797-1 retail MAC. PACE negotiates: it may use the
// same 3DES suite, or AES at 128, 192 or 256 bits with CMAC.
//
// They differ in more than the cipher. AES uses a 16-byte block (so padding
// and the send-sequence counter are 16 bytes too) and derives a fresh IV for
// every message by encrypting the counter, where 3DES uses a zero IV
// throughout. Getting either detail wrong produces a session that handshakes
// cleanly and then fails on the first real command, so both are expressed here
// once rather than being re-decided at each call site.

/// How a session's keys are derived and how many bytes they are.
enum CipherAlgorithm { desEde2, aes }

abstract class CipherSuite {
  const CipherSuite();

  CipherAlgorithm get algorithm;

  /// Bytes in a cipher block — also the padding unit and the counter width.
  int get blockSize;

  /// Bytes in a derived session key.
  int get keyLength;

  /// ICAO 9303 §9.7.1 key derivation: hash the shared secret with a 4-byte
  /// counter and take the leading key bytes. The counter distinguishes the
  /// encryption key (1), the MAC key (2) and the password key (3).
  Uint8List deriveKey(Uint8List secret, int counter);

  Uint8List encrypt(Uint8List key, Uint8List paddedData, {Uint8List? ssc});
  Uint8List decrypt(Uint8List key, Uint8List data, {Uint8List? ssc});

  /// Authenticates [data], which the caller has already padded. [ssc] is
  /// prepended by the caller, not here — the two suites agree on that much.
  Uint8List mac(Uint8List key, Uint8List data);

  /// The PACE authentication token over an unpadded encoding.
  ///
  /// Separate from [mac] because the two suites genuinely differ here: the
  /// retail MAC needs block-aligned input so the caller must pad, while CMAC
  /// pads internally and padding it first CHANGES the result — an exact block
  /// multiple takes a different branch of the algorithm. Feeding one suite's
  /// convention to the other produces a token the chip rejects, at the last
  /// step of the handshake.
  Uint8List token(Uint8List key, Uint8List data);

  Uint8List padTo(Uint8List data) => crypto.padToBlock(data, blockSize);
}

/// Two-key 3DES with the retail MAC — what BAC always uses, and one of the
/// options PACE may negotiate.
class DesEde2Suite extends CipherSuite {
  const DesEde2Suite();

  @override
  CipherAlgorithm get algorithm => CipherAlgorithm.desEde2;
  @override
  int get blockSize => 8;
  @override
  int get keyLength => 16;

  @override
  Uint8List deriveKey(Uint8List secret, int counter) =>
      crypto.deriveKey(secret, counter);

  @override
  Uint8List encrypt(Uint8List key, Uint8List paddedData, {Uint8List? ssc}) =>
      crypto.desEde2Cbc(key, paddedData, encrypt: true);

  @override
  Uint8List decrypt(Uint8List key, Uint8List data, {Uint8List? ssc}) =>
      crypto.desEde2Cbc(key, data, encrypt: false);

  @override
  Uint8List mac(Uint8List key, Uint8List data) => crypto.retailMac(key, data);

  @override
  Uint8List token(Uint8List key, Uint8List data) => mac(key, padTo(data));
}

/// AES-CBC with CMAC, at 128, 192 or 256 bits. Only PACE reaches this.
class AesSuite extends CipherSuite {
  /// Key length in bytes: 16, 24 or 32.
  @override
  final int keyLength;

  const AesSuite(this.keyLength);

  @override
  CipherAlgorithm get algorithm => CipherAlgorithm.aes;
  @override
  int get blockSize => 16;

  @override
  Uint8List deriveKey(Uint8List secret, int counter) {
    // AES-128 keeps SHA-1; the longer keys need SHA-256 to have enough output.
    if (keyLength == 16) return _truncate(crypto.deriveDigestSha1(secret, counter), 16);
    return _truncate(_sha256(secret, counter), keyLength);
  }

  @override
  Uint8List encrypt(Uint8List key, Uint8List paddedData, {Uint8List? ssc}) =>
      _cbc(key, paddedData, _iv(key, ssc), encrypt: true);

  @override
  Uint8List decrypt(Uint8List key, Uint8List data, {Uint8List? ssc}) =>
      _cbc(key, data, _iv(key, ssc), encrypt: false);

  @override
  Uint8List mac(Uint8List key, Uint8List data) =>
      // ICAO truncates the 16-byte CMAC to its leading 8 bytes.
      Uint8List.sublistView(aesCmac(key, data), 0, 8);

  @override
  Uint8List token(Uint8List key, Uint8List data) => mac(key, data);

  /// AES derives a per-message IV by encrypting the send-sequence counter, so
  /// two identical commands never produce identical ciphertext. A zero IV here
  /// (the 3DES convention) would leak that they were the same.
  Uint8List _iv(Uint8List key, Uint8List? ssc) {
    if (ssc == null) return Uint8List(blockSize);
    final engine = pc.AESEngine()..init(true, pc.KeyParameter(key));
    final out = Uint8List(blockSize);
    engine.processBlock(ssc, 0, out, 0);
    return out;
  }

  static Uint8List _cbc(
    Uint8List key,
    Uint8List data,
    Uint8List iv, {
    required bool encrypt,
  }) {
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final out = Uint8List(data.length);
    for (var off = 0; off < data.length; off += 16) {
      cipher.processBlock(data, off, out, off);
    }
    return out;
  }

  static Uint8List _sha256(Uint8List secret, int counter) {
    final input = BytesBuilder()
      ..add(secret)
      ..add(Uint8List.fromList([0, 0, 0, counter]));
    return Uint8List.fromList(c.sha256.convert(input.toBytes()).bytes);
  }

  static Uint8List _truncate(Uint8List digest, int n) =>
      Uint8List.fromList(digest.sublist(0, n));
}

/// The suite BAC always runs on.
const bacCipherSuite = DesEde2Suite();
