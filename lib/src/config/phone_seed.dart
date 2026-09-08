import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import 'dial_codes.g.dart';

// ─── Phone field helpers ─────────────────────────────────────────────────────
//
// The pure half of phone_number_input.dart (200-line rule): splitting a value
// handed down from above into a dial-code country + national digits, national
// grouping for display, and real validity from the country's numbering plan.
// The widget owns the controller and the caret; nothing here touches either.

/// Split a value handed down from above (the register's number, a restored
/// session) into the dial-code country to adopt and the national digits.
///
/// An E.164 ("+2348031234567") is matched against the dial-code table,
/// preferring [currentIso] when its code matches, since +1 alone cannot say
/// US or CA. Bare digits are national digits for [currentIso]; [iso] is then
/// null, meaning "keep the country you have".
({String? iso, String digits}) splitPhoneSeed(String raw, String currentIso) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (!trimmed.startsWith('+') || digits.isEmpty) return (iso: null, digits: digits);
  final currentDial = kDialCodes[currentIso] ?? '234';
  String? matchedIso;
  var matchedDial = '';
  if (digits.startsWith(currentDial)) {
    matchedIso = currentIso;
    matchedDial = currentDial;
  } else {
    kDialCodes.forEach((iso, dial) {
      if (digits.startsWith(dial) && dial.length > matchedDial.length) {
        matchedIso = iso;
        matchedDial = dial;
      }
    });
  }
  if (matchedIso == null) return (iso: null, digits: digits);
  return (iso: matchedIso, digits: digits.substring(matchedDial.length));
}

/// National-format the raw digits for display ("8031234567" → "803 123 4567").
/// Falls back to the bare digits when the country has no known format.
String formatNationalDigits(String raw, String iso) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  try {
    final parsed = PhoneNumber.parse(
      digits,
      callerCountry: IsoCode.values.byName(iso),
      destinationCountry: IsoCode.values.byName(iso),
    );
    final formatted = parsed.formatNsn();
    return formatted.isEmpty ? digits : formatted;
  } catch (_) {
    return digits;
  }
}

/// Real validity from the country's numbering plan, mirroring the web SDK's
/// libphonenumber check: a wrong-length NG number is rejected while a
/// legitimately short number elsewhere is not. Falls back to the 6–15 digit
/// length guess for a country the parser does not cover, rather than blocking
/// the user on it.
bool phoneDigitsValid(String digits, String iso) {
  final fallback = digits.length >= 6 && digits.length <= 15;
  try {
    return PhoneNumber.parse(
      digits,
      callerCountry: IsoCode.values.byName(iso),
      destinationCountry: IsoCode.values.byName(iso),
    ).isValid();
  } catch (_) {
    return fallback;
  }
}
