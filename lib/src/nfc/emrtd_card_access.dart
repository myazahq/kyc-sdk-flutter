import 'dart:typed_data';

import 'emrtd_pace_params.dart';
import 'emrtd_tlv.dart';

// ─── EF.CardAccess (ICAO 9303 Part 11, §9.2.11) ───────────────────────────────
//
// A small file at the Master File level, readable WITHOUT any session, which is
// how a terminal learns whether the chip speaks PACE and with which parameters.
// It is a DER SET of SecurityInfo structures; each is a SEQUENCE whose first
// element is an object identifier naming a protocol.
//
// Most entries are for protocols this SDK does not run (chip authentication,
// terminal authentication). Those are skipped rather than treated as errors —
// a file we only partly understand is the normal case, not a failure.

/// One PACE offering from the chip.
class PaceOffer {
  final PaceProtocol protocol;

  /// The standardised domain-parameter id, naming a curve or DH group.
  final int? parameterId;

  const PaceOffer({required this.protocol, this.parameterId});

  @override
  String toString() => '$protocol params=$parameterId';
}

/// The PACE offerings advertised in EF.CardAccess, in file order.
///
/// Returns empty for a chip that advertises no PACE at all, for a file that
/// cannot be parsed, and for one that is simply absent — all of which mean the
/// same thing to the caller: use BAC.
List<PaceOffer> parseCardAccess(Uint8List file) {
  final offers = <PaceOffer>[];
  try {
    // The file is a SET (0x31) of SEQUENCEs. Some chips wrap it differently, so
    // accept the SET's contents or a bare run of SEQUENCEs.
    final outer = parseTlv(file);
    final body = outer.tag == 0x31 ? outer.value : file;

    for (final info in parseTlvSequence(body)) {
      if (info.tag != 0x30) continue; // not a SecurityInfo
      final fields = parseTlvSequence(info.value);
      if (fields.isEmpty || fields.first.tag != 0x06) continue;

      final protocol = paceProtocolFromOid(fields.first.value);
      if (protocol == null) continue; // some other protocol's security info

      // PACEInfo ::= SEQUENCE { protocol OID, version INTEGER,
      //                         parameterId INTEGER OPTIONAL }
      final ints = fields.skip(1).where((f) => f.tag == 0x02).toList();
      final parameterId = ints.length > 1 ? tlvInt(ints[1].value) : null;

      offers.add(PaceOffer(protocol: protocol, parameterId: parameterId));
    }
  } on TlvError {
    return const [];
  }
  return offers;
}

/// The offering to actually attempt, or null when none is usable.
///
/// Prefers the strongest cipher the chip offers among the variants this build
/// supports, so a chip advertising both AES-256 and 3DES is run at AES-256.
PaceOffer? selectPaceOffer(List<PaceOffer> offers) {
  PaceOffer? best;
  for (final offer in offers) {
    if (!offer.protocol.isSupported) continue;
    if (offer.parameterId == null) continue;
    if (paceCurveForParameterId(offer.parameterId!) == null) continue;
    if (best == null ||
        offer.protocol.suite.keyLength > best.protocol.suite.keyLength) {
      best = offer;
    }
  }
  return best;
}

/// Why no offering was usable — for logging, and for the honest message that a
/// document needing an unimplemented variant still reads over BAC.
PaceUnsupported? paceGapFor(List<PaceOffer> offers) {
  if (offers.isEmpty) return null;
  for (final offer in offers) {
    if (offer.protocol.keyAgreement != PaceKeyAgreement.ecdh) {
      return PaceUnsupported.keyAgreement;
    }
    if (offer.protocol.mapping != PaceMapping.generic) {
      return PaceUnsupported.mapping;
    }
  }
  return PaceUnsupported.domainParameters;
}
