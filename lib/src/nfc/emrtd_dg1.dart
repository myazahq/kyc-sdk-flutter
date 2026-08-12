import 'dart:convert';
import 'dart:typed_data';

import '../services/mrz_parser.dart';
import 'emrtd_tlv.dart';

// ---------------------------------------------------------------------------
// THE CHIP'S OWN MRZ.
//
// DG1 is the machine-readable zone exactly as the ISSUING STATE wrote it, and
// passive authentication hashes it against the signed security object. It is
// the strongest copy of the holder's details the document carries.
//
// The camera scan is a GUESS at the same characters and is not a safe
// substitute for display. Measured on a real Nigerian passport: the on-device
// recogniser read the first '<' of the '<<' surname separator as 'K', so
// `INGWE<<RICHARD<UNIMKE` arrived as `INGWEK<RICHARD...`. The name split then
// never fired at the surname boundary and landed in the trailing filler,
// producing "KKKK INGWEK RICHARD UNIMKE" under a caption promising we had read
// the secure chip.
//
// TD3 carries NO check digit over the name field (only line 2 is protected), so
// that corruption passes `parseMrz` validation silently. It cannot be detected
// from the scan alone, which is why the chip has to be the source once we hold
// it. Mirrors the React Native SDK's emrtd/dg1.ts.
// ---------------------------------------------------------------------------

/// DG1's outer template, and the MRZ element inside it.
const int _tagDg1Template = 0x61;
const int _tagMrz = 0x5f1f;

/// The MRZ read off the chip, or null when DG1 is absent, malformed, or not a
/// size [parseMrz] recognises.
///
/// Null is a normal outcome the caller falls back from, never an error: the
/// read itself already succeeded and its bytes still go to the server, which
/// parses DG1 authoritatively regardless of what this returns.
MrzScan? parseDg1(String? dg1Base64) {
  if (dg1Base64 == null || dg1Base64.isEmpty) return null;
  try {
    final bytes = Uint8List.fromList(base64Decode(dg1Base64));
    // Two explicit levels rather than a recursive search: DG1's shape is fixed
    // by ICAO 9303, so there is nothing to discover.
    final template = findTlv(bytes, _tagDg1Template);
    if (template == null) return null;
    final mrz = findTlv(template.value, _tagMrz);
    if (mrz == null) return null;
    return parseMrz(String.fromCharCodes(mrz.value));
  } catch (_) {
    // Display path only. A malformed DG1 must never take down the success
    // screen of a read that otherwise worked.
    return null;
  }
}
