import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_extras.dart';

// EF.COM declares which data groups a chip holds. Reading it lets us ask only
// for the optional groups that exist, instead of probing for three that may not
// — each miss is a failed SELECT against a document somebody is holding still.
//
// Mirrors the RN SDK's parseComDataGroups tests.
Uint8List _com(List<int> dgTags) {
  // 60 L  5C L <tags>  — the shape EF.COM actually has.
  final list = [0x5c, dgTags.length, ...dgTags];
  return Uint8List.fromList([0x60, list.length, ...list]);
}

void main() {
  test('reads the declared groups', () {
    // 0x67 = DG7, 0x6B = DG11, 0x6C = DG12.
    expect(parseComDataGroups(_com([0x67, 0x6B])), {7, 11});
    expect(parseComDataGroups(_com([0x6C])), {12});
  });

  test('ignores tags for groups we never read', () {
    // DG3/DG4 (fingerprints, iris) are EAC-protected and reserved for
    // government terminals. A chip declaring them must not make us ask.
    final parsed = parseComDataGroups(_com([0x63, 0x76, 0x67]));
    expect(parsed, {7});
  });

  test('an empty declaration means the chip holds none of them', () {
    expect(parseComDataGroups(_com([])), isEmpty);
  });

  test('returns null on anything it cannot read, rather than throwing', () {
    // Null means "ask for all of them": an unreadable COM is ordinary — a chip
    // lifted mid-read — and it must not take the session with it. A THROW here
    // would cost the banked DG1/SOD/DG2.
    expect(parseComDataGroups(Uint8List.fromList([0x61, 0x02, 0x00, 0x00])), isNull);
    expect(parseComDataGroups(Uint8List.fromList([0x60])), isNull);
    expect(parseComDataGroups(Uint8List(0)), isNull);
    // Declared shape, but no data-group list inside.
    expect(parseComDataGroups(Uint8List.fromList([0x60, 0x02, 0x5f, 0x00])), isNull);
  });
}
