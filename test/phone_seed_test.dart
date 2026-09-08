import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/phone_seed.dart';

// ─── The phone field's pure half ─────────────────────────────────────────────
//
// Split out of the widget (200-line rule), so its rules are pinned here rather
// than only on a device: an E.164 decides its own dial code, +1 prefers the
// country already picked, bare digits are national, and validity comes from
// the numbering plan rather than a length guess.

void main() {
  group('splitPhoneSeed', () {
    test('an E.164 decides its own dial code', () {
      final seed = splitPhoneSeed('+2348031234567', 'GB');
      expect(seed.iso, 'NG');
      expect(seed.digits, '8031234567');
    });

    test('a shared dial code prefers the country already picked', () {
      // +1 alone cannot say US or CA; the current pick breaks the tie.
      expect(splitPhoneSeed('+14155550123', 'CA').iso, 'CA');
      expect(splitPhoneSeed('+14155550123', 'US').iso, 'US');
    });

    test('bare digits are national digits for the current country', () {
      final seed = splitPhoneSeed('803 123 4567', 'NG');
      expect(seed.iso, isNull);
      expect(seed.digits, '8031234567');
    });

    test('an empty or unmatched value keeps the country', () {
      expect(splitPhoneSeed('', 'NG').iso, isNull);
      expect(splitPhoneSeed('+', 'NG').digits, '');
    });
  });

  group('formatNationalDigits + phoneDigitsValid', () {
    test('groups an NG number and judges it by the plan', () {
      expect(formatNationalDigits('8031234567', 'NG'), '803 123 4567');
      expect(phoneDigitsValid('8031234567', 'NG'), isTrue);
      expect(phoneDigitsValid('80312345', 'NG'), isFalse);
    });

    test('falls back to the digits and the length guess for an unknown country',
        () {
      expect(formatNationalDigits('12345678', 'ZZ'), '12345678');
      expect(phoneDigitsValid('12345678', 'ZZ'), isTrue);
      expect(phoneDigitsValid('12', 'ZZ'), isFalse);
    });
  });
}
