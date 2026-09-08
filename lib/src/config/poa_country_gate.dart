// ─── The Proof of Address step's country gate ────────────────────────────────
//
// On the ADDRESS scope the declared country is the applicant's own claim about
// their market: it picks the document kinds on offer, the PoA vendor market
// and rides the submission as the verification's country, and the scope seeds
// none (see AddressCountryControl). A document uploaded with no country behind
// it is therefore not yet a complete answer, so Continue holds until one is
// declared (user decision 2026-09-08). Elsewhere the flow's own country stands
// and the gate never bites; an org that accepts exactly ONE country has the
// control show it as a settled fact, which counts as declared.
//
// A THREE-WAY MIRROR of the web SDK's lib/poa-country-gate.ts and the RN
// SDK's lib/poa-country-gate.ts; change the rule in one and change all three.

/// Whether the Proof of Address step may continue as far as the COUNTRY is
/// concerned (the upload has its own gate).
bool poaCountryDeclared({
  required String? scope,
  required String? selectedCountry,
  required List<String> offered,
}) {
  if (scope != 'address') return true;
  if (selectedCountry != null && selectedCountry.trim().isNotEmpty) return true;
  return offered.length == 1;
}
