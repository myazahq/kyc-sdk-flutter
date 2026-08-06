import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/currency_flags.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/amount_input_formatter.dart';

TextEditingValue _v(String text, [int? caret]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    );

String _format(String input, {int decimalDigits = 2}) =>
    AmountInputFormatter(decimalDigits: decimalDigits)
        .formatEditUpdate(const TextEditingValue(), _v(input))
        .text;

void main() {
  group('AmountInputFormatter', () {
    test('groups thousands', () {
      expect(_format('250000'), '250,000');
      expect(_format('1000'), '1,000');
      expect(_format('999'), '999');
      expect(_format('1234567'), '1,234,567');
    });

    test('keeps decimals and caps them', () {
      expect(_format('1234.5'), '1,234.5');
      expect(_format('1234.56'), '1,234.56');
      expect(_format('1234.5678'), '1,234.56');
    });

    test('ignores a second decimal point', () {
      expect(_format('12.34.56'), '12.34');
    });

    test('strips non-numeric input', () {
      expect(_format('abc250x000'), '250,000');
    });

    test('decimalDigits 0 makes it integer-only', () {
      expect(_format('1234.99', decimalDigits: 0), '1,234');
    });

    test('empty input clears the field', () {
      expect(_format(''), '');
      expect(_format('abc'), '');
    });

    test('caret stays after the digit just typed', () {
      // Typing '0' at the end of "25000" → "250,000" with the caret at the end.
      const f = AmountInputFormatter();
      final out = f.formatEditUpdate(_v('25,000'), _v('250000'));
      expect(out.text, '250,000');
      expect(out.selection.baseOffset, 7);
    });

    test('caret is remapped when editing mid-number', () {
      // Caret after the first 3 significant chars of "1234567".
      const f = AmountInputFormatter();
      final out = f.formatEditUpdate(const TextEditingValue(), _v('1234567', 3));
      expect(out.text, '1,234,567');
      // 3 significant chars = "1","2","3" → position right after the '3'.
      expect(out.text.substring(0, out.selection.baseOffset).replaceAll(',', ''),
          '123');
    });
  });

  group('currencyFlagCountry', () {
    test('derives the country from the ISO 4217 prefix', () {
      expect(currencyFlagCountry('NGN'), 'NG');
      expect(currencyFlagCountry('USD'), 'US');
      expect(currencyFlagCountry('GBP'), 'GB');
      expect(currencyFlagCountry('KES'), 'KE');
      expect(currencyFlagCountry('ZAR'), 'ZA');
    });

    test('maps EUR to the EU flag', () {
      expect(currencyFlagCountry('EUR'), 'EU');
    });

    test('returns null for supranational codes', () {
      expect(currencyFlagCountry('XOF'), isNull);
      expect(currencyFlagCountry('XAF'), isNull);
      expect(currencyFlagCountry('XAU'), isNull);
    });

    test('returns null for malformed input', () {
      expect(currencyFlagCountry(''), isNull);
      expect(currencyFlagCountry('NG'), isNull);
    });
  });
}
