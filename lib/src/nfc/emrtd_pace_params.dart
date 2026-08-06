import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'emrtd_cipher.dart';

// ─── PACE protocols and domain parameters (ICAO 9303 Part 11, §9.2) ───────────
//
// A chip advertises which PACE variant it supports as an object identifier in
// EF.CardAccess, plus a number naming the elliptic curve or DH group to run it
// over. This file turns both into something usable.
//
// Only Generic Mapping is implemented, and only over elliptic curves — see
// [PaceUnsupported] below for why, and for what happens to the passports that
// need something else.

/// How the chip's nonce is mapped onto a fresh generator.
enum PaceMapping { generic, integrated, chipAuthentication }

/// Which key-agreement primitive the mapping runs over.
enum PaceKeyAgreement { dh, ecdh }

/// A PACE variant the chip advertised.
class PaceProtocol {
  /// The raw OID bytes, which are re-sent to the chip and folded into the
  /// authentication tokens — so they must be preserved exactly as received.
  final Uint8List oid;
  final PaceMapping mapping;
  final PaceKeyAgreement keyAgreement;
  final CipherSuite suite;

  const PaceProtocol({
    required this.oid,
    required this.mapping,
    required this.keyAgreement,
    required this.suite,
  });

  /// Whether this build can actually run it.
  bool get isSupported =>
      mapping == PaceMapping.generic && keyAgreement == PaceKeyAgreement.ecdh;

  @override
  String toString() =>
      'PACE-${keyAgreement.name.toUpperCase()}-${mapping.name} '
      '${suite.algorithm.name}/${suite.keyLength * 8}';
}

/// `0.4.0.127.0.7.2.2.4` — the arc every PACE protocol identifier sits under.
const _paceArc = [0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02, 0x04];

/// The last-but-one arc component selects mapping + key agreement.
const _branches = <int, (PaceMapping, PaceKeyAgreement)>{
  1: (PaceMapping.generic, PaceKeyAgreement.dh),
  2: (PaceMapping.generic, PaceKeyAgreement.ecdh),
  3: (PaceMapping.integrated, PaceKeyAgreement.dh),
  4: (PaceMapping.integrated, PaceKeyAgreement.ecdh),
  6: (PaceMapping.chipAuthentication, PaceKeyAgreement.ecdh),
};

/// The final component selects the cipher suite.
const _ciphers = <int, CipherSuite>{
  1: DesEde2Suite(),
  2: AesSuite(16),
  3: AesSuite(24),
  4: AesSuite(32),
};

/// Decodes a PACE protocol OID. Returns null if it is not a PACE identifier at
/// all — an unknown OID in EF.CardAccess is normal, since the file also carries
/// security information for protocols we do not run.
PaceProtocol? paceProtocolFromOid(Uint8List oid) {
  if (oid.length != _paceArc.length + 2) return null;
  for (var i = 0; i < _paceArc.length; i++) {
    if (oid[i] != _paceArc[i]) return null;
  }
  final branch = _branches[oid[_paceArc.length]];
  final suite = _ciphers[oid[_paceArc.length + 1]];
  if (branch == null || suite == null) return null;
  return PaceProtocol(
    oid: Uint8List.fromList(oid),
    mapping: branch.$1,
    keyAgreement: branch.$2,
    suite: suite,
  );
}

// ─── Standardised domain parameters (ICAO 9303 / BSI TR-03110) ────────────────
//
// The chip names its curve by number rather than sending the parameters, so
// both sides must agree on this table. Ids 0–2 are DH groups and 3–7 are
// reserved; everything from 8 up is an elliptic curve.

const _curveNames = <int, String>{
  8: 'secp192r1',
  9: 'brainpoolp192r1',
  10: 'secp224r1',
  11: 'brainpoolp224r1',
  12: 'secp256r1',
  13: 'brainpoolp256r1',
  14: 'brainpoolp320r1',
  15: 'secp384r1',
  16: 'brainpoolp384r1',
  17: 'brainpoolp512r1',
  18: 'secp521r1',
};

/// The curve for a standardised parameter id, or null when the id names a DH
/// group (0–2), is reserved, or is unknown.
pc.ECDomainParameters? paceCurveForParameterId(int id) {
  final name = _curveNames[id];
  if (name == null) return null;
  return pc.ECDomainParameters(name);
}

/// Why a chip's PACE offering cannot be run here.
///
/// Both cases fall back to BAC rather than failing the read, so a passport that
/// lands here behaves exactly as it did before PACE existed in this SDK.
enum PaceUnsupported {
  /// Integrated Mapping or Chip Authentication Mapping. Rare in issued
  /// documents, and each is a distinct protocol rather than a variation.
  mapping,

  /// PACE over finite-field Diffie-Hellman. Deliberately not implemented: it
  /// needs the RFC 5114 modular groups embedded as constants, and a subtly
  /// wrong 2048-bit prime produces a handshake that fails in a way that looks
  /// like a bad document. Virtually all issued passports offer the elliptic
  /// curve variants, and any chip reaching here still reads over BAC.
  keyAgreement,

  /// The named curve is not one of the standardised ids.
  domainParameters,
}
