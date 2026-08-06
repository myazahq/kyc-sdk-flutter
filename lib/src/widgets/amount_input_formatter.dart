import 'package:flutter/services.dart';

// ─── Amount input formatter ───────────────────────────────────────────────────
//
// Groups thousands as the user types (250000 → 250,000) and caps the decimals,
// matching the web SDK's money input. Long figures are the norm for the
// expected-volume question in low-denomination currencies, and an ungrouped
// "250000" is genuinely hard to read back.
//
// The caret is remapped rather than pinned to the end: grouping inserts commas
// to the LEFT of the caret, so without this an edit in the middle of the number
// would jump the cursor.

class AmountInputFormatter extends TextInputFormatter {
  /// Decimal places allowed. 0 makes the field integer-only.
  final int decimalDigits;

  const AmountInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final caret = newValue.selection.baseOffset;

    // How many non-separator characters precede the caret — the anchor that
    // survives regrouping.
    var significantBefore = 0;
    for (var i = 0; i < caret && i < text.length; i++) {
      if (text[i] != ',') significantBefore++;
    }

    final cleaned = _clean(text);
    if (cleaned.isEmpty) return const TextEditingValue();

    final dot = cleaned.indexOf('.');
    final whole = dot == -1 ? cleaned : cleaned.substring(0, dot);
    final fraction = dot == -1 ? '' : cleaned.substring(dot);
    final grouped = _group(whole) + fraction;

    var offset = grouped.length;
    if (significantBefore == 0) {
      offset = 0;
    } else {
      var counted = 0;
      for (var i = 0; i < grouped.length; i++) {
        if (grouped[i] != ',') counted++;
        if (counted >= significantBefore) {
          offset = i + 1;
          break;
        }
      }
    }

    return TextEditingValue(
      text: grouped,
      selection:
          TextSelection.collapsed(offset: offset.clamp(0, grouped.length)),
    );
  }

  /// Keeps digits plus at most one '.', truncating past [decimalDigits].
  String _clean(String input) {
    final out = StringBuffer();
    var seenDot = false;
    var decimals = 0;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '.') {
        // Integer-only: everything past the point is fractional, so DROP the
        // rest. Merely skipping the '.' would splice "1234.99" into "123499".
        if (decimalDigits == 0) break;
        if (seenDot) continue;
        seenDot = true;
        out.write(ch);
        continue;
      }
      final code = ch.codeUnitAt(0);
      if (code < 0x30 || code > 0x39) continue; // not 0-9
      if (seenDot) {
        if (decimals >= decimalDigits) continue;
        decimals++;
      }
      out.write(ch);
    }
    return out.toString();
  }

  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final out = StringBuffer();
    final lead = digits.length % 3;
    var i = 0;
    if (lead > 0) {
      out.write(digits.substring(0, lead));
      i = lead;
    }
    while (i < digits.length) {
      if (out.isNotEmpty) out.write(',');
      out.write(digits.substring(i, i + 3));
      i += 3;
    }
    return out.toString();
  }
}

/// Numeric value of a grouped amount string ("250,000.50" → 250000.5).
double? parseGroupedAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());
