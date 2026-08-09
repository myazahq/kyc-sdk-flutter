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

// ─── Currency → full name ─────────────────────────────────────────────────────
//
// The picker shows the name beside the code, because "GHS" and "GMD" are one
// letter apart and mean different money. Covers Myaza's operating region in
// full plus the majors and the currencies a workflow is realistically offered;
// an unlisted code falls back to the code alone rather than a guess.
//
// Keep in step with the React Native SDK's `config/currencyFlags.ts`.

const Map<String, String> _currencyNames = {
  // ── Africa ────────────────────────────────────────────────────────────────
  'NGN': 'Nigerian Naira',
  'GHS': 'Ghanaian Cedi',
  'KES': 'Kenyan Shilling',
  'ZAR': 'South African Rand',
  'XOF': 'West African CFA Franc',
  'XAF': 'Central African CFA Franc',
  'EGP': 'Egyptian Pound',
  'MAD': 'Moroccan Dirham',
  'TND': 'Tunisian Dinar',
  'DZD': 'Algerian Dinar',
  'ETB': 'Ethiopian Birr',
  'UGX': 'Ugandan Shilling',
  'TZS': 'Tanzanian Shilling',
  'RWF': 'Rwandan Franc',
  'ZMW': 'Zambian Kwacha',
  'BWP': 'Botswana Pula',
  'NAD': 'Namibian Dollar',
  'MUR': 'Mauritian Rupee',
  'MWK': 'Malawian Kwacha',
  'MZN': 'Mozambican Metical',
  'AOA': 'Angolan Kwanza',
  'SLL': 'Sierra Leonean Leone',
  'SLE': 'Sierra Leonean Leone',
  'LRD': 'Liberian Dollar',
  'GMD': 'Gambian Dalasi',
  'GNF': 'Guinean Franc',
  'CDF': 'Congolese Franc',
  'BIF': 'Burundian Franc',
  'SOS': 'Somali Shilling',
  'SDG': 'Sudanese Pound',
  'LYD': 'Libyan Dinar',
  'ZWL': 'Zimbabwean Dollar',
  'SZL': 'Swazi Lilangeni',
  'LSL': 'Lesotho Loti',
  'CVE': 'Cape Verdean Escudo',
  'STN': 'São Tomé & Príncipe Dobra',
  'SCR': 'Seychellois Rupee',
  'DJF': 'Djiboutian Franc',
  'ERN': 'Eritrean Nakfa',
  'MGA': 'Malagasy Ariary',
  'MRU': 'Mauritanian Ouguiya',
  'KMF': 'Comorian Franc',
  'SSP': 'South Sudanese Pound',

  // ── Majors / widely held ──────────────────────────────────────────────────
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
  'CAD': 'Canadian Dollar',
  'AUD': 'Australian Dollar',
  'NZD': 'New Zealand Dollar',
  'CHF': 'Swiss Franc',
  'JPY': 'Japanese Yen',
  'CNY': 'Chinese Yuan',
  'HKD': 'Hong Kong Dollar',
  'SGD': 'Singapore Dollar',
  'INR': 'Indian Rupee',
  'AED': 'UAE Dirham',
  'SAR': 'Saudi Riyal',
  'QAR': 'Qatari Riyal',
  'KWD': 'Kuwaiti Dinar',
  'TRY': 'Turkish Lira',
  'ILS': 'Israeli Shekel',
  'SEK': 'Swedish Krona',
  'NOK': 'Norwegian Krone',
  'DKK': 'Danish Krone',
  'PLN': 'Polish Zloty',
  'CZK': 'Czech Koruna',
  'RON': 'Romanian Leu',
  'BRL': 'Brazilian Real',
  'MXN': 'Mexican Peso',
  'ARS': 'Argentine Peso',
  'CLP': 'Chilean Peso',
  'COP': 'Colombian Peso',
  'ZMK': 'Zambian Kwacha',
  'PKR': 'Pakistani Rupee',
  'BDT': 'Bangladeshi Taka',
  'LKR': 'Sri Lankan Rupee',
  'PHP': 'Philippine Peso',
  'THB': 'Thai Baht',
  'MYR': 'Malaysian Ringgit',
  'IDR': 'Indonesian Rupiah',
  'VND': 'Vietnamese Dong',
  'KRW': 'South Korean Won',
};

/// Full name for a currency code, or null when we don't have one — callers show
/// the bare code rather than inventing a name.
String? currencyName(String currency) =>
    _currencyNames[currency.trim().toUpperCase()];
