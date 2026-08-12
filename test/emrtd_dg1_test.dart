import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/emrtd_dg1.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/mrz_parser.dart';

// The real document this was found on: a Nigerian passport read over PACE.
//
// Line 2 is BUILT with `mrzCheckDigit` rather than typed out. Hand-writing check
// digits produces a fixture that fails for a reason unrelated to what is being
// tested, and one whose digits happened to be wrong in the same way as the code
// would pass while proving nothing.
const _doc = 'B51305135';
const _dob = '990725';
const _expiry = '341029';

final String _l1 = 'P<NGAINGWE<<RICHARD<UNIMKE'.padRight(44, '<');

String _buildLine2() {
  // Joined rather than `+`-composed: an MRZ line is POSITIONAL, so one field
  // per row (each with its own note) is the readable form, and `+` on
  // non-literals trips prefer_interpolation_to_compose_strings — which CI
  // treats as a failure. Interpolating the whole line into one string would
  // satisfy the lint by destroying exactly the layout that makes it checkable.
  final head = [
    _doc,
    mrzCheckDigit(_doc).toString(),
    'NGA',
    _dob,
    mrzCheckDigit(_dob).toString(),
    'M',
    _expiry,
    mrzCheckDigit(_expiry).toString(),
    '<' * 14, // personal number: unused
    '<', // ...and its check digit, which the parser accepts as filler
  ].join();
  final composite =
      head.substring(0, 10) + head.substring(13, 20) + head.substring(21, 43);
  return head + mrzCheckDigit(composite).toString();
}

/// DG1 as the chip returns it: 61 <len> 5F1F <len> <mrz>.
///
/// The outer length covers the inner element ENTIRE — its two tag bytes, its
/// length byte, and its value — so it is `mrz.length + 3`, not + 4.
String _dg1(String mrz) {
  final chars = mrz.codeUnits;
  final bytes = Uint8List.fromList(
    [0x61, chars.length + 3, 0x5f, 0x1f, chars.length, ...chars],
  );
  return base64Encode(bytes);
}

void main() {
  final l2 = _buildLine2();
  final mrz = _l1 + l2;

  group('parseDg1', () {
    test('reads the holder name off the chip exactly', () {
      final scan = parseDg1(_dg1(mrz));
      expect(scan?.lastName, 'INGWE');
      expect(scan?.firstName, 'RICHARD UNIMKE');
      expect(scan?.documentNumber, 'B51305135');
    });

    test('returns null rather than throwing on absent or malformed DG1', () {
      expect(parseDg1(null), isNull);
      expect(parseDg1(''), isNull);
      expect(parseDg1('not base64 at all \$\$\$'), isNull);
      expect(parseDg1(_dg1('TOO SHORT')), isNull);
    });

    // The defect this module exists for. The on-device recogniser read the
    // FIRST '<' of the '<<' surname separator as 'K'. Line 2 is untouched, so
    // every check digit still validates and the scan is accepted: the name is
    // silently wrong and nothing in the MRZ can tell, because TD3 carries no
    // check digit over the name field.
    test('is immune to the camera misread that mangled the holder name', () {
      final misread = _l1
          .replaceFirst('INGWE<<RICHARD', 'INGWEK<RICHARD')
          .replaceRange(40, 44, 'KKKK');
      expect(misread.length, 44);

      final fromCamera = parseMrz(misread + l2);
      // It validates. That is the trap.
      expect(fromCamera, isNotNull);
      expect(fromCamera!.displayName, 'KKKK INGWEK RICHARD UNIMKE');

      // The chip is unaffected by whatever the camera thought it saw.
      expect(parseDg1(_dg1(mrz))!.displayName, 'RICHARD UNIMKE INGWE');
    });
  });
}
