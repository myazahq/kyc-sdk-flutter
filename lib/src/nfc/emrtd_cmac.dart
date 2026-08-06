import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

// ─── AES-CMAC (RFC 4493 / NIST SP 800-38B) ────────────────────────────────────
//
// Written out here rather than taken from pointycastle, whose CMac builds its
// zero IV with the KEY length instead of the cipher's block size. With AES-128
// those are both 16 bytes so it works by coincidence; with AES-192 or AES-256 it
// throws outright — and those are exactly the suites a modern passport
// negotiates for PACE.
//
// The algorithm is short and its published test vectors are checked in
// emrtd_cipher_test.dart.

const int _blockSize = 16;

/// The constant that keeps the subkey doubling inside the field, for a
/// 128-bit block.
const int _rb = 0x87;

/// Full 16-byte CMAC of [data] under [key]. Callers truncate as their protocol
/// requires — eMRTD takes the leading 8 bytes.
Uint8List aesCmac(Uint8List key, Uint8List data) {
  final cipher = pc.AESEngine()..init(true, pc.KeyParameter(key));

  // Subkeys: encrypt a zero block, then double once for K1 and again for K2.
  final l = _encryptBlock(cipher, Uint8List(_blockSize));
  final k1 = _double(l);
  final k2 = _double(k1);

  final blocks = (data.length + _blockSize - 1) ~/ _blockSize;
  // An empty message still has one (padded) block.
  final lastIsWhole = data.isNotEmpty && data.length % _blockSize == 0;
  final count = blocks == 0 ? 1 : blocks;

  var x = Uint8List(_blockSize);
  for (var i = 0; i < count - 1; i++) {
    final block = Uint8List.sublistView(data, i * _blockSize, (i + 1) * _blockSize);
    x = _encryptBlock(cipher, _xor(x, block));
  }

  // The final block is XORed with K1 when it is complete, or padded and XORed
  // with K2 when it is not. That distinction is the whole reason CMAC must not
  // be handed externally padded input.
  final start = (count - 1) * _blockSize;
  final Uint8List last;
  if (lastIsWhole) {
    last = _xor(Uint8List.sublistView(data, start), k1);
  } else {
    final tail = Uint8List(_blockSize);
    final remaining = data.length - start;
    tail.setRange(0, remaining, Uint8List.sublistView(data, start));
    tail[remaining] = 0x80;
    last = _xor(tail, k2);
  }

  return _encryptBlock(cipher, _xor(x, last));
}

Uint8List _encryptBlock(pc.BlockCipher cipher, Uint8List input) {
  final out = Uint8List(_blockSize);
  cipher.processBlock(input, 0, out, 0);
  return out;
}

/// Left-shift by one bit, folding in the field constant when the top bit was
/// set.
Uint8List _double(Uint8List input) {
  final out = Uint8List(_blockSize);
  var carry = 0;
  for (var i = _blockSize - 1; i >= 0; i--) {
    final v = (input[i] << 1) | carry;
    out[i] = v & 0xFF;
    carry = (v >> 8) & 0x01;
  }
  if ((input[0] & 0x80) != 0) out[_blockSize - 1] ^= _rb;
  return out;
}

Uint8List _xor(Uint8List a, Uint8List b) {
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] ^ b[i];
  }
  return out;
}
