import '../services/api_service.dart';
import 'business.dart';
import 'business_application.dart';

// ─── Turning the register's officer list into rows the applicant confirms ────
//
// This is the whole point of checking at selection: the question stops being
// "who are your directors?", which is a memory test, and becomes "are these
// right?", which is a confirmation. It also makes a removal meaningful —
// taking a name out of a list you were shown is a decision, and the server
// records it as one (keyPeople.removedFromRegistry).
//
// Ported from the web SDK's key-people-prefill.ts — keep the two in lockstep.

/// People a register names who are not parties to the business: the agent who
/// filed the papers, the witness to a signature, the lawyer who drew them up,
/// the deponent who swore the declaration. Prefilled as directors, an
/// applicant confirming what looked like their own board would hand us the
/// filing agent as an officer.
const _notAParty = ['presenter', 'witness', 'lawyer', 'deponent', 'solicitor', 'notary'];

/// A registry designation in our role vocabulary.
///
/// Falls back to `director` rather than dropping a person: an officer we
/// cannot classify still has to appear — an unlisted one reads as an omission.
KeyPersonRole prefillRoleFromDesignation(String? designation) {
  final d = (designation ?? '').toLowerCase();
  // Nigeria's beneficial-ownership register, in CAMA 2020's own words.
  if (d.contains('significant control') || d.contains('psc') || d.contains('beneficial')) {
    return KeyPersonRole.beneficialOwner;
  }
  if (d.contains('shareholder') || d.contains('owner') || d.contains('member')) {
    return KeyPersonRole.shareholder;
  }
  if (d.contains('secretary') || d.contains('signator')) return KeyPersonRole.signatory;
  return KeyPersonRole.director;
}

/// A stake as the field holds it: a whole number where that is honest, so a
/// register's 33 does not arrive as "33.0" in a box the applicant then edits.
String _pctText(double pct) =>
    pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toString();

Set<String> _words(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.length >= 2)
    .toSet();

/// Two spellings of one name: enough shared words, and no CONFLICT.
///
/// Counting shared words alone merged siblings — a double-barrelled family
/// surname supplies two shared words by itself. Each side holding a word the
/// other lacks is a different person; one side holding extras is the fuller
/// spelling. Mirrors the server's namesLikelySame.
bool samePerson(String a, String b) {
  final wa = _words(a);
  final wb = _words(b);
  if (wa.isEmpty || wb.isEmpty) return false;
  final shared = wa.intersection(wb).length;
  if (shared == 1 && (wa.length == 1 || wb.length == 1)) return true;
  if (shared < 2) return false;
  return shared == wa.length || shared == wb.length;
}

/// Build the rows to start the step with.
///
/// ONE ROW PER PERSON: a register files one designation per entry and the same
/// human several times over, so entries are merged by name, keeping the
/// classification that asks the most of them.
List<KeyPersonEntry> prefillKeyPeople(
  List<RegistryOfficer> officers,
  String defaultCountry,
) {
  final rows = <KeyPersonEntry>[];
  for (final o in officers) {
    final name = (o.name ?? '').trim();
    if (name.isEmpty) continue;
    final d = (o.designation ?? '').toLowerCase();
    if (_notAParty.any(d.contains)) continue;

    final role = prefillRoleFromDesignation(o.designation);
    final existingIndex = rows.indexWhere((r) => samePerson(r.name, name));
    if (existingIndex >= 0) {
      final existing = rows[existingIndex];
      // Keep the classification that asks the most of them: somebody filed as
      // both a director and a person with significant control is the latter.
      rows[existingIndex] = existing.copyWith(
        role: role == KeyPersonRole.beneficialOwner ? role : existing.role,
        name: name.length > existing.name.length ? name : existing.name,
        // A register files one designation per entry, so the same person's
        // email or stake may sit on the OTHER filing. Take whichever entry
        // carried it; never overwrite a value with a blank.
        email: existing.email.trim().isEmpty
            ? (o.email ?? '').trim()
            : existing.email,
        ownershipPct: existing.ownershipPct.trim().isEmpty &&
                o.ownershipPct != null &&
                o.ownershipPct!.isFinite
            ? _pctText(o.ownershipPct!)
            : existing.ownershipPct,
        registrationNumber: existing.registrationNumber.trim().isEmpty
            ? (o.registrationNumber ?? '').trim()
            : existing.registrationNumber,
      );
      continue;
    }
    rows.add(KeyPersonEntry(
      name: name,
      role: role,
      // Fill what the register actually SAID and invent nothing: a value it
      // did not give stays empty for the applicant. Both of these were being
      // dropped, so the split it had already computed and the email it holds
      // were retyped by hand or, for the email, simply left blank until the
      // step refused to continue.
      email: (o.email ?? '').trim(),
      ownershipPct: o.ownershipPct != null && o.ownershipPct!.isFinite
          ? _pctText(o.ownershipPct!)
          : '',
      country: defaultCountry,
      // The register's own word wins; null is silence, not a denial, so the
      // name heuristic answers only when it said nothing.
      isCorporate: o.isCorporate ?? looksCorporate(name),
      registrationNumber: (o.registrationNumber ?? '').trim(),
    ));
  }
  return rows;
}

/// Whether prefilling would overwrite work. Only ever fills an empty list:
/// someone who already typed a name has told us something the register did
/// not, and replacing it would lose both their input and the signal in it.
bool shouldPrefill(List<KeyPersonEntry> existing) =>
    existing.every((r) => r.name.trim().isEmpty && r.email.trim().isEmpty);
