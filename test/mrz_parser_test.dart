import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/mrz_extract.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/mrz_parser.dart';

// The canonical TD3 specimen from ICAO 9303 Part 3 (Utopia / ANNA MARIA
// ERIKSSON). Using the spec's own example means the check-digit maths is
// verified against the standard rather than against our own assumptions.
const _td3Line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const _td3Line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

void main() {
  group('mrzCheckDigit', () {
    test('matches the ICAO worked examples', () {
      expect(mrzCheckDigit('520727'), 3);
      expect(mrzCheckDigit('AB2134<<<'), 5);
    });
  });

  group('parseMrz TD3', () {
    test('parses the ICAO specimen', () {
      final scan = parseMrz('$_td3Line1$_td3Line2', now: DateTime(2026));
      expect(scan, isNotNull);
      expect(scan!.format, 'TD3');
      expect(scan.documentNumber, 'L898902C3');
      expect(scan.dateOfBirth, DateTime(1974, 8, 12));
      expect(scan.dateOfExpiry, DateTime(2012, 4, 15));
      expect(scan.lastName, 'ERIKSSON');
      expect(scan.firstName, 'ANNA MARIA');
      expect(scan.nationality, 'UTO');
    });

    test('rejects a corrupted check digit', () {
      // Flip the document-number check digit 6 → 7.
      final bad = _td3Line2.replaceRange(9, 10, '7');
      expect(parseMrz('$_td3Line1$bad', now: DateTime(2026)), isNull);
    });

    test('rejects a wrong-length MRZ', () {
      expect(parseMrz(_td3Line1, now: DateTime(2026)), isNull);
    });
  });

  group('extractMrz', () {
    test('finds the MRZ among ordinary page text', () {
      final scan = extractMrz([
        'PASSPORT',
        'Type P  Code UTO',
        'Surname ERIKSSON',
        _td3Line1,
        _td3Line2,
      ], now: DateTime(2026));
      expect(scan?.documentNumber, 'L898902C3');
    });

    test('handles a recognizer that merges both lines', () {
      final scan =
          extractMrz(['$_td3Line1$_td3Line2'], now: DateTime(2026));
      expect(scan?.documentNumber, 'L898902C3');
    });

    test('recovers a line clipped of trailing filler', () {
      // Recognizers routinely drop the last '<' or two.
      final clipped = _td3Line1.substring(0, 43);
      final scan = extractMrz([clipped, _td3Line2], now: DateTime(2026));
      expect(scan?.documentNumber, 'L898902C3');
    });

    test('ignores frames with no MRZ', () {
      expect(extractMrz(['Hello', 'World']), isNull);
    });
  });
}
