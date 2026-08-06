// ─── Currency → flag country ──────────────────────────────────────────────────
//
// ISO 4217 currency codes are built from the ISO 3166 country code plus a
// letter for the currency itself (NG + N = NGN, US + D = USD), so the first two
// characters give the right flag for almost every real currency.
//
// Two exceptions matter and are handled explicitly:
//   • EUR — no country prefix; use the EU flag.
//   • X-prefixed codes — supranational/commodity (XOF, XAF, XCD, XAU…). These
//     have no single country, so they get NO flag rather than a wrong one
//     (XO isn't a country; rendering something arbitrary is worse than blank).

const Map<String, String> _explicit = {
  'EUR': 'EU',
};

/// ISO-3166 alpha-2 code whose flag represents [currency], or null when no
/// single country does.
String? currencyFlagCountry(String currency) {
  final code = currency.trim().toUpperCase();
  if (code.length < 3) return null;

  final explicit = _explicit[code];
  if (explicit != null) return explicit;

  // Supranational / metal codes carry no country.
  if (code.startsWith('X')) return null;

  return code.substring(0, 2);
}
