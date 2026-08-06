import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart' as pc;

// ─── eMRTD crypto primitives (ICAO 9303 Part 11) ──────────────────────────────
//
// The small set of operations BAC is built from: two-key 3DES in CBC mode, the
// ISO 9797-1 Algorithm 3 "retail MAC", and the key-derivation function.
//
// Deliberately plain: pointycastle supplies the block ciphers and `crypto` the
// digests, and everything here is the standard's own construction on top of
// them. Every function is checked against the worked example in ICAO 9303
// Part 11 Appendix D, which is why this can be trusted without a passport in
// hand — see emrtd_crypto_test.dart.

/// Cipher-block size for DES/3DES, and the unit padding aligns to.
const int kBlockSize = 8;

/// ISO/IEC 9797-1 padding method 2: append 0x80, then zeros to a block edge.
/// Applied to plaintext before encryption AND to data before MACing.
Uint8List padToBlock(Uint8List data, int blockSize) {
  final out = BytesBuilder()..add(data)..addByte(0x80);
  while (out.length % blockSize != 0) {
    out.addByte(0x00);
  }
  return out.toBytes();
}

/// Strips ISO 9797-1 method 2 padding. Returns the input unchanged if it does
/// not end in a valid padding run — a chip that pads differently should not
/// cost us the data.
Uint8List unpadFromBlock(Uint8List data, int blockSize) {
  for (var i = data.length - 1; i >= 0 && data.length - i <= blockSize; i--) {
    if (data[i] == 0x80) return Uint8List.sublistView(data, 0, i);
    if (data[i] != 0x00) break;
  }
  return data;
}

/// The 8-byte-block forms, which is everything BAC uses.
Uint8List pad(Uint8List data) => padToBlock(data, kBlockSize);
Uint8List unpad(Uint8List data) => unpadFromBlock(data, kBlockSize);

/// Two-key 3DES (K1|K2|K1) in CBC mode with a zero IV, as BAC specifies.
Uint8List desEde2Cbc(Uint8List key16, Uint8List data, {required bool encrypt}) {
  final key24 = Uint8List(24)
    ..setRange(0, 16, key16)
    ..setRange(16, 24, key16.sublist(0, 8));
  final cipher = pc.CBCBlockCipher(pc.DESedeEngine())
    ..init(
      encrypt,
      pc.ParametersWithIV(pc.KeyParameter(key24), Uint8List(kBlockSize)),
    );
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += kBlockSize) {
    cipher.processBlock(data, off, out, off);
  }
  return out;
}

/// Single DES from the 3DES engine.
///
/// pointycastle ships no standalone DES block cipher, but 3DES with all three
/// key blocks equal reduces to plain DES — E(D(E(x))) with one key is E(x) —
/// so K|K|K gives exactly the primitive the retail MAC needs.
pc.BlockCipher _des(Uint8List key8, {required bool encrypt}) {
  final k = Uint8List(24)
    ..setRange(0, 8, key8)
    ..setRange(8, 16, key8)
    ..setRange(16, 24, key8);
  return pc.DESedeEngine()..init(encrypt, pc.KeyParameter(k));
}

/// ISO 9797-1 Algorithm 3 MAC ("retail MAC") with DES, 3DES on the final block.
///
/// Single-DES-CBC the whole message under the first half of the key, then
/// decrypt the last block with the second half and re-encrypt with the first.
/// [data] must already be padded.
Uint8List retailMac(Uint8List key16, Uint8List data) {
  final k1 = Uint8List.sublistView(key16, 0, 8);
  final k2 = Uint8List.sublistView(key16, 8, 16);

  // CBC by hand: the engine is a raw block cipher, and chaining is one XOR.
  final enc1 = _des(k1, encrypt: true);
  var chain = Uint8List(kBlockSize);
  final block = Uint8List(kBlockSize);
  for (var off = 0; off < data.length; off += kBlockSize) {
    final input = Uint8List(kBlockSize);
    for (var i = 0; i < kBlockSize; i++) {
      input[i] = data[off + i] ^ chain[i];
    }
    enc1.processBlock(input, 0, block, 0);
    chain = Uint8List.fromList(block);
  }

  final tmp = Uint8List(kBlockSize);
  _des(k2, encrypt: false).processBlock(chain, 0, tmp, 0);
  final mac = Uint8List(kBlockSize);
  _des(k1, encrypt: true).processBlock(tmp, 0, mac, 0);
  return mac;
}

/// Sets the (ignored) DES parity bits so keys match the standard's examples.
Uint8List adjustParity(Uint8List key) {
  final out = Uint8List.fromList(key);
  for (var i = 0; i < out.length; i++) {
    var b = out[i];
    var ones = 0;
    for (var bit = 1; bit < 8; bit++) {
      if ((b & (1 << bit)) != 0) ones++;
    }
    // Odd parity in the low bit.
    b = ones.isEven ? (b | 0x01) : (b & 0xFE);
    out[i] = b;
  }
  return out;
}

/// SHA-1 over a shared secret plus a 4-byte counter — the raw digest, before
/// any key-specific treatment. [counter] is 1 for the encryption key, 2 for the
/// MAC key, 3 for the PACE password key.
Uint8List deriveDigestSha1(Uint8List seed, int counter) {
  final input = BytesBuilder()
    ..add(seed)
    ..add(Uint8List.fromList([0, 0, 0, counter]));
  return Uint8List.fromList(c.sha1.convert(input.toBytes()).bytes);
}

/// ICAO 9303 key-derivation for 3DES: the leading 16 digest bytes, parity
/// adjusted. AES keys skip the parity step — that is a DES-only convention.
Uint8List deriveKey(Uint8List seed, int counter) =>
    adjustParity(Uint8List.sublistView(deriveDigestSha1(seed, counter), 0, 16));

/// The MRZ information used to unlock the chip, in the exact form BAC hashes:
/// document number, date of birth and expiry, each followed by its check digit.
String mrzKeySeedInput({
  required String documentNumber,
  required String dateOfBirth,
  required String dateOfExpiry,
}) {
  String field(String v) => '$v${_checkDigit(v)}';
  return field(documentNumber.padRight(9, '<')) +
      field(dateOfBirth) +
      field(dateOfExpiry);
}

/// Kseed: the first 16 bytes of SHA-1 over the MRZ information.
Uint8List keySeed({
  required String documentNumber,
  required String dateOfBirth,
  required String dateOfExpiry,
}) {
  final info = mrzKeySeedInput(
    documentNumber: documentNumber,
    dateOfBirth: dateOfBirth,
    dateOfExpiry: dateOfExpiry,
  );
  final digest = c.sha1.convert(info.codeUnits).bytes;
  return Uint8List.fromList(digest.sublist(0, 16));
}

/// ICAO 7-3-1 weighted check digit over the MRZ alphabet.
int _checkDigit(String value) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < value.length; i++) {
    final ch = value.codeUnitAt(i);
    final int v;
    if (ch >= 0x30 && ch <= 0x39) {
      v = ch - 0x30; // 0-9
    } else if (ch >= 0x41 && ch <= 0x5A) {
      v = ch - 0x41 + 10; // A-Z
    } else {
      v = 0; // '<' and anything unexpected
    }
    sum += v * weights[i % 3];
  }
  return sum % 10;
}
