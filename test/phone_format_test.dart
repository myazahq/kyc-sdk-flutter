import 'package:flutter_test/flutter_test.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

// Guards the two behaviours the phone field relies on: national grouping for
// display, and REAL validity from the country's numbering plan rather than the
// 6–15 digit length guess the field used to make. Pinned here because both come
// from the parser package, so an upgrade that changed either would otherwise
// only surface on a device.

String format(String digits, String iso) {
  final parsed = PhoneNumber.parse(
    digits,
    callerCountry: IsoCode.values.byName(iso),
    destinationCountry: IsoCode.values.byName(iso),
  );
  return parsed.formatNsn();
}

bool isValid(String digits, String iso) => PhoneNumber.parse(
      digits,
      callerCountry: IsoCode.values.byName(iso),
      destinationCountry: IsoCode.values.byName(iso),
    ).isValid();

void main() {
  group('national formatting', () {
    test('groups a Nigerian mobile number', () {
      final out = format('8031234567', 'NG');
      expect(out.replaceAll(RegExp(r'\s'), ''), '8031234567');
      expect(out, contains(' ')); // actually grouped, not passed through
    });

    test('groups a UK mobile number', () {
      final out = format('7911123456', 'GB');
      expect(out.replaceAll(RegExp(r'\s'), ''), '7911123456');
    });

    test('leaves a partial number usable while typing', () {
      expect(() => format('803', 'NG'), returnsNormally);
    });
  });

  group('validity', () {
    test('accepts a real Nigerian mobile number', () {
      expect(isValid('8031234567', 'NG'), isTrue);
    });

    test('rejects a wrong-length Nigerian number', () {
      // 6 digits passed the old length-only heuristic; the numbering plan
      // rejects it.
      expect(isValid('803123', 'NG'), isFalse);
    });

    test('rejects an obviously invalid prefix', () {
      expect(isValid('0000000000', 'NG'), isFalse);
    });
  });
}
