import '../services/api_business.dart';

// ─── Copy what the register returned into the form, without overwriting ──────
//
// Only empty fields are filled: an applicant who typed something before the
// lookup meant it, and the register is a starting point here rather than the
// last word. Every value stays editable either way. Returns the patch AND the
// keys it filled, so a company change can clear exactly those and leave the
// applicant's own answers alone. Mirrors the web SDK's prefillFromRegister and
// the RN SDK's registerPrefillPatch — keep the three in lockstep.
//
// Keys are the canonical business field names ('registrationName', 'address',
// 'companyType', 'email', 'phone', 'taxId', 'vatNumber', 'natureOfBusiness',
// 'dateOfIncorporation') — the same vocabulary `setBusinessField` speaks.

({Map<String, String> patch, List<String> prefilled}) registerPrefillPatch(
  BusinessCompanyRecord? company,
  Map<String, String> current,
) {
  final patch = <String, String>{};
  if (company == null) return (patch: patch, prefilled: const []);

  // Field by field, from the register's answer to the form's question. The
  // register does not answer all of these for every company, so each is
  // filled only when it actually came back.
  void fill(String key, String? value) {
    if (value != null &&
        value.isNotEmpty &&
        (current[key] ?? '').trim().isEmpty) {
      patch[key] = value;
    }
  }

  fill('registrationName', company.name);
  // The register splits the address across lines; the form has one box, so
  // they are joined rather than dropping the parts that did not fit.
  final address = [company.address, company.city, company.state]
      .whereType<String>()
      .where((p) => p.isNotEmpty)
      .join(', ');
  fill('address', address.isEmpty ? null : address);
  fill('companyType', company.typeOfEntity);
  fill('email', company.email);
  fill('phone', company.phone);
  fill('taxId', company.taxId);
  fill('vatNumber', company.vatNumber);
  fill('natureOfBusiness', company.natureOfBusiness);
  // The register gives an incorporation DATE; the field wants YYYY-MM-DD, and
  // anything it cannot be read as is left blank rather than guessed at.
  fill('dateOfIncorporation', isoDateOnly(company.registrationDate));

  return (patch: patch, prefilled: patch.keys.toList(growable: false));
}

/// The date part of an ISO timestamp, or null.
///
/// Deliberately NOT `DateTime.parse`/`tryParse` leniency. A lenient parser is
/// wrong in exactly the dangerous direction: it reads "12/03/2018" in an order
/// nobody chose (a register returning DD/MM means 12 March) and rolls invalid
/// dates forward. Each of those is a confidently wrong date written into a
/// compliance form, which is worse than an empty field somebody fills in
/// themselves. So only an unambiguous ISO date is accepted, and the calendar
/// is checked afterwards so 2018-02-31 does not roll into March.
String? isoDateOnly(String? value) {
  if (value == null) return null;
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T\s]|$)').firstMatch(value.trim());
  if (match == null) return null;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final parsed = DateTime.utc(y, m, d);
  // A real date, not one that rolled over into the next month.
  if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
  return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
}
