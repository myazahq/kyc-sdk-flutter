// ─── MRZ parsing (ICAO 9303) ──────────────────────────────────────────────────
//
// Parses the Machine Readable Zone off a document's photo page: TD3 (passports,
// 2×44) and TD1 (ID cards, 3×30), validated with the 7-3-1 check digits.
// Mirrors the server's src/lib/nfc/mrz.ts so both sides agree on the same
// document.
//
// Unlike the server — which reads EXACT bytes off the chip's DG1 — this parses
// OCR output, which misreads characters. Two defences:
//   1. Numeric-only fields (dates, check digits) get an OCR confusion pass
//      (O→0, I→1, S→5, …) before validation.
//   2. Nothing is accepted unless every check digit passes. That makes a bad
//      frame self-rejecting: the scanner simply keeps looking.

const List<int> _weights = [7, 3, 1];

/// 7-3-1 weighted modulus-10 check digit over an MRZ field.
int mrzCheckDigit(String field) {
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    final c = field.codeUnitAt(i);
    // '0'-'9' → 0-9, 'A'-'Z' → 10-35, '<' (and anything else) → 0.
    final v = c >= 48 && c <= 57
        ? c - 48
        : c >= 65 && c <= 90
            ? c - 55
            : 0;
    sum += v * _weights[i % 3];
  }
  return sum % 10;
}

bool _digitOk(String field, String cd) {
  final fixed = _toDigits(cd);
  if (fixed.length != 1) return false;
  final code = fixed.codeUnitAt(0);
  if (code < 48 || code > 57) return false;
  return mrzCheckDigit(field) == code - 48;
}

/// Maps letters OCR commonly returns for digits. Only ever applied to fields
/// the spec says are numeric — never to names or the document number, where a
/// letter may be genuine.
String _toDigits(String s) => s
    .replaceAll('O', '0')
    .replaceAll('Q', '0')
    .replaceAll('D', '0')
    .replaceAll('U', '0')
    .replaceAll('I', '1')
    .replaceAll('L', '1')
    .replaceAll('Z', '2')
    .replaceAll('S', '5')
    .replaceAll('G', '6')
    .replaceAll('T', '7')
    .replaceAll('B', '8');

DateTime? _mrzDate(String raw, {required bool expiry, required DateTime now}) {
  final yymmdd = _toDigits(raw);
  if (yymmdd.length != 6 || int.tryParse(yymmdd) == null) return null;
  final yy = int.parse(yymmdd.substring(0, 2));
  final mm = int.parse(yymmdd.substring(2, 4));
  final dd = int.parse(yymmdd.substring(4, 6));
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  // Birth dates pivot on the current year; expiry pivots at 70 (eMRTD validity
  // is ≤10 years, so 70+ must be 19xx).
  final nowYY = now.year % 100;
  final century = expiry ? (yy >= 70 ? 1900 : 2000) : (yy > nowYY ? 1900 : 2000);
  return DateTime(century + yy, mm, dd);
}

String? _clean(String s) {
  final v = s.replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return v.isEmpty ? null : v;
}

/// The fields the BAC key needs, plus the biodata worth showing back.
class MrzScan {
  final String format; // TD1 | TD3
  final String documentNumber;
  final DateTime dateOfBirth;
  final DateTime dateOfExpiry;
  final String? firstName;
  final String? lastName;
  final String? nationality;

  const MrzScan({
    required this.format,
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
    this.firstName,
    this.lastName,
    this.nationality,
  });

  String get displayName =>
      [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');
}

MrzScan? _parseTd3(String l1, String l2, DateTime now) {
  final docNumber = l2.substring(0, 9);
  final dob = l2.substring(13, 19);
  final expiry = l2.substring(21, 27);
  final personal = l2.substring(28, 42);
  final personalCd = l2[42];
  final composite =
      l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 43);

  final valid = _digitOk(docNumber, l2[9]) &&
      _digitOk(dob, l2[19]) &&
      _digitOk(expiry, l2[27]) &&
      // An empty personal number may carry '<' or '0' as its check digit.
      (_clean(personal) == null
          ? personalCd == '<' || personalCd == '0'
          : _digitOk(personal, personalCd)) &&
      _digitOk(composite, l2[43]);
  if (!valid) return null;

  final birth = _mrzDate(dob, expiry: false, now: now);
  final expires = _mrzDate(expiry, expiry: true, now: now);
  final number = _clean(docNumber)?.replaceAll(' ', '');
  if (birth == null || expires == null || number == null) return null;

  final names = l1.substring(5).split('<<');
  return MrzScan(
    format: 'TD3',
    documentNumber: number,
    dateOfBirth: birth,
    dateOfExpiry: expires,
    lastName: _clean(names.isNotEmpty ? names.first : ''),
    firstName: _clean(names.skip(1).join(' ')),
    nationality: _clean(l2.substring(10, 13)),
  );
}

MrzScan? _parseTd1(String l1, String l2, String l3, DateTime now) {
  final docNumber = l1.substring(5, 14);
  final dob = l2.substring(0, 6);
  final expiry = l2.substring(8, 14);
  final composite = l1.substring(5, 30) +
      l2.substring(0, 7) +
      l2.substring(8, 15) +
      l2.substring(18, 29);

  final valid = _digitOk(docNumber, l1[14]) &&
      _digitOk(dob, l2[6]) &&
      _digitOk(expiry, l2[14]) &&
      _digitOk(composite, l2[29]);
  if (!valid) return null;

  final birth = _mrzDate(dob, expiry: false, now: now);
  final expires = _mrzDate(expiry, expiry: true, now: now);
  final number = _clean(docNumber)?.replaceAll(' ', '');
  if (birth == null || expires == null || number == null) return null;

  final names = l3.split('<<');
  return MrzScan(
    format: 'TD1',
    documentNumber: number,
    dateOfBirth: birth,
    dateOfExpiry: expires,
    lastName: _clean(names.isNotEmpty ? names.first : ''),
    firstName: _clean(names.skip(1).join(' ')),
    nationality: _clean(l2.substring(15, 18)),
  );
}

/// Parses a continuous MRZ string (88 chars = TD3, 90 = TD1). Returns null when
/// it isn't syntactically valid or any check digit fails.
MrzScan? parseMrz(String text, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final flat = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9<]'), '');
  if (flat.length == 88) {
    return _parseTd3(flat.substring(0, 44), flat.substring(44), at);
  }
  if (flat.length == 90) {
    return _parseTd1(
        flat.substring(0, 30), flat.substring(30, 60), flat.substring(60), at);
  }
  return null;
}
