import 'dart:typed_data';

import 'emrtd_session.dart';
import 'emrtd_tlv.dart';

// The OPTIONAL data groups — DG7 (the displayed signature image), DG11
// (additional personal details) and DG12 (additional document details).
//
// The Flutter port of the RN SDK's emrtd/extras.ts. Keep the two in lockstep.
//
// None of them changes a verdict: the server hash-verifies each against the SOD
// exactly as it does DG2, records what they said, and moves on. They are read
// LAST and every read is best-effort — losing one costs that group, never the
// session's banked result.
//
// DG3 and DG4 (fingerprints, iris) are NEVER read. They are EAC-protected and
// reserved for government terminals; we are not one.

/// Elementary file ids for the optional groups.
class _ExtraEf {
  static const dg7 = 0x0107;
  static const dg11 = 0x010B;
  static const dg12 = 0x010C;

  /// EF.COM lists the data groups the chip DECLARES it holds.
  static const com = 0x011E;
}

/// EF.COM's tag byte for each data group we care about.
const _tagToDg = <int, int>{0x67: 7, 0x6B: 11, 0x6C: 12};

/// Whatever the chip declares in EF.COM, or null when it cannot be read.
///
/// Null means "ask for all of them": a chip with an unreadable COM may still
/// hold the groups, and a probe costs one failed SELECT.
Set<int>? parseComDataGroups(Uint8List com) {
  // parseTlv THROWS on malformed input — an unreadable COM is ordinary (a
  // chip that left contact mid-read), so it must not take the session with it.
  final Tlv outer;
  try {
    outer = parseTlv(com);
  } catch (_) {
    return null;
  }
  if (outer.tag != 0x60) return null;
  final list = findTlv(outer.value, 0x5c);
  if (list == null) return null;
  final present = <int>{};
  for (final byte in list.value) {
    final dg = _tagToDg[byte];
    if (dg != null) present.add(dg);
  }
  return present;
}

/// The optional groups, as raw file bytes. Null where absent or unreadable.
class ExtraGroupReads {
  const ExtraGroupReads({this.dg7, this.dg11, this.dg12});

  final Uint8List? dg7;
  final Uint8List? dg11;
  final Uint8List? dg12;

  bool get isEmpty => dg7 == null && dg11 == null && dg12 == null;
}

Future<Uint8List?> _readOptional(EmrtdSession session, int fileId) async {
  try {
    return await session.readFile(fileId);
  } catch (_) {
    // Absent, or the chip left contact. Either way it costs this group alone.
    return null;
  }
}

/// Read whichever of DG7/DG11/DG12 the chip declares (or, without a readable
/// COM, whichever answer).
Future<ExtraGroupReads> readExtraGroups(EmrtdSession session) async {
  final com = await _readOptional(session, _ExtraEf.com);
  final declared = com == null ? null : parseComDataGroups(com);
  bool want(int dg) => declared == null || declared.contains(dg);

  return ExtraGroupReads(
    dg7: want(7) ? await _readOptional(session, _ExtraEf.dg7) : null,
    dg11: want(11) ? await _readOptional(session, _ExtraEf.dg11) : null,
    dg12: want(12) ? await _readOptional(session, _ExtraEf.dg12) : null,
  );
}
