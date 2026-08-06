import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'emrtd_pace.dart';

// ─── Elliptic-curve helpers for PACE ──────────────────────────────────────────
//
// Split from the handshake itself so the protocol reads as protocol. The
// validation here is the part worth attention: a chip that chooses a point off
// the curve, or the point at infinity, can learn our private scalar from how we
// respond, so those are refused rather than used.

(BigInt, pc.ECPoint) generateKeyPair(pc.ECDomainParameters curve, Random rng) {
  final d = randomScalar(curve, rng);
  return (d, (curve.G * d)!);
}

/// A private scalar in [1, n-1], rejection-sampled so the distribution stays
/// uniform rather than biased toward small values by a modulo.
BigInt randomScalar(pc.ECDomainParameters curve, Random rng) {
  final n = curve.n;
  final bytes = (n.bitLength + 7) ~/ 8;
  while (true) {
    final candidate = toBigInt(
      Uint8List.fromList(List.generate(bytes, (_) => rng.nextInt(256))),
    );
    if (candidate > BigInt.zero && candidate < n) return candidate;
  }
}

Uint8List encodePoint(pc.ECPoint point) => point.getEncoded(false);

pc.ECPoint decodePoint(pc.ECDomainParameters curve, Uint8List bytes) {
  final pc.ECPoint point;
  try {
    point = curve.curve.decodePoint(bytes)!;
  } catch (_) {
    throw const PaceError('read_failed', 'the chip sent an unreadable key');
  }
  // A point off the curve or at infinity would leak our private scalar to a
  // chip that chose it deliberately, so it is refused rather than used.
  if (point.isInfinity || !isOnCurve(curve, point)) {
    throw const PaceError('read_failed', 'the chip sent an invalid key');
  }
  return point;
}

/// Checks y² = x³ + ax + b, in the curve's own field arithmetic so the modulus
/// never has to be extracted.
bool isOnCurve(pc.ECDomainParameters curve, pc.ECPoint point) {
  try {
    final x = point.x!;
    final y = point.y!;
    final a = curve.curve.a!;
    final b = curve.curve.b!;
    final lhs = y.square();
    final rhs = (x.square() * x) + (a * x) + b;
    return lhs.toBigInteger() == rhs.toBigInteger();
  } catch (_) {
    return false;
  }
}

BigInt toBigInt(Uint8List bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  return n;
}

/// The shared secret is the agreed point's x coordinate, left-padded to the
/// curve's field width — a short value must not shorten the key derivation.
Uint8List fieldBytes(pc.ECDomainParameters curve, BigInt value) {
  final width = (curve.curve.fieldSize + 7) ~/ 8;
  final out = Uint8List(width);
  var v = value;
  for (var i = width - 1; i >= 0 && v > BigInt.zero; i--) {
    out[i] = (v & BigInt.from(0xFF)).toInt();
    v = v >> 8;
  }
  return out;
}

bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
