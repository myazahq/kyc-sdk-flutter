import 'country_names.g.dart';

// ─── Country names ───────────────────────────────────────────────────────────
//
// Countries are ISO-3166 alpha-2 strings, not a fixed enum — the SDK supports
// "Global Documents" (any ISO country can verify via Document Intelligence / NFC
// where the org is granted access). The full ISO name table lives in the
// generated `country_names.g.dart` (kCountryNames + kRegionByCode).

/// Human label for an ISO-2 country code, falling back to the upper-cased code.
String countryLabel(String code) =>
    kCountryNames[code.toUpperCase()] ?? code.toUpperCase();

// ─── Scan sides ───────────────────────────────────────────────────────────────

enum ScanSides {
  frontOnly,
  frontAndBack;
}

/// Parses a server-sent scan-sides token (`front_and_back` / `frontAndBack` /
/// `front` / `front_only`) into a [ScanSides]. Returns null when unset/unknown
/// so the resolver can apply its own default.
ScanSides? parseScanSides(String? raw) {
  if (raw == null) return null;
  final v = raw.replaceAll('-', '_').toLowerCase();
  if (v == 'front_and_back' || v == 'frontandback' || v == 'both') {
    return ScanSides.frontAndBack;
  }
  if (v == 'front' || v == 'front_only' || v == 'frontonly') {
    return ScanSides.frontOnly;
  }
  return null;
}

// ─── ID type definition ───────────────────────────────────────────────────────
//
// A resolved definition for one (country, idType) pair. Curated entries below
// carry the exact truths for the gov-DB provider countries; for any other
// granted pair a definition is synthesized from the server config row (see
// [resolveIdTypeDefinition]). This mirrors the web SDK's `resolveIdTypeDefinition`
// — local curated wins, server row fills the gap.

class IdTypeConfig {
  /// Stable server key, e.g. `bvn`, `drivers-license`, `passport`.
  final String key;
  final String label;

  /// What the user actually types when it differs from the ID's name — e.g.
  /// Tax ID lookups are keyed off the person's NIN, so the input asks for a NIN.
  final String? inputLabel;
  final bool requiresDocumentCapture;
  final ScanSides? scanSides;
  final int? digits;
  final RegExp? pattern;

  /// Whether this document carries an ICAO 9303 eMRTD chip (passports
  /// everywhere, plus curated chip cards like the Ghana Card and CI CNI). Drives
  /// whether the NFC chip step (Phase 2) is offered. Catalogue-driven, never a
  /// hardcoded country map.
  final bool supportsNfc;

  const IdTypeConfig({
    required this.key,
    required this.label,
    this.inputLabel,
    required this.requiresDocumentCapture,
    this.scanSides,
    this.digits,
    this.pattern,
    this.supportsNfc = false,
  });
}

// ─── Curated definitions (keyed by ISO-2 country) ─────────────────────────────

const Map<String, List<IdTypeConfig>> kCuratedIdTypes = {
  'NG': [
    IdTypeConfig(
      key: 'bvn',
      label: 'BVN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      key: 'bvn-premium',
      label: 'BVN Premium',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      key: 'tax-id',
      label: 'Tax ID',
      inputLabel: 'NIN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      key: 'nin',
      label: 'NIN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      key: 'vnin',
      label: 'vNIN',
      requiresDocumentCapture: false,
      digits: 16,
    ),
    IdTypeConfig(
      key: 'passport',
      label: 'International Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
      supportsNfc: true,
    ),
    IdTypeConfig(
      key: 'drivers-license',
      label: "Driver's License",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      key: 'pvc',
      label: "Voter's Card",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
  'GH': [
    IdTypeConfig(
      key: 'ghana-card',
      label: 'Ghana Card',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
      supportsNfc: true,
    ),
    IdTypeConfig(
      key: 'voters',
      label: "Voter's Card",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      key: 'drivers-license',
      label: "Driver's License",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      key: 'ssnit',
      label: 'SSNIT',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
    ),
    IdTypeConfig(
      key: 'passport',
      label: 'Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
      supportsNfc: true,
    ),
  ],
  'KE': [
    IdTypeConfig(
      key: 'national-id',
      label: 'National ID',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      key: 'passport',
      label: 'Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
      supportsNfc: true,
    ),
  ],
  'ZA': [
    IdTypeConfig(
      key: 'national-id',
      label: 'National ID',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
  'CI': [
    IdTypeConfig(
      key: 'cni',
      label: 'CNI',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
      supportsNfc: true,
    ),
    IdTypeConfig(
      key: 'residence-card',
      label: 'Residence Card',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
};

/// Back-compat alias for the old constant name.
const Map<String, List<IdTypeConfig>> kIdTypesByCountry = kCuratedIdTypes;

// ─── Lookups & resolution ─────────────────────────────────────────────────────

/// All curated [IdTypeConfig]s for the given ISO-2 [country] (empty when the
/// country has no curated entries — Global-Document countries resolve from the
/// server config instead).
List<IdTypeConfig> curatedIdTypesForCountry(String country) =>
    kCuratedIdTypes[country.toUpperCase()] ?? const [];

/// Curated definition for a (country, key) pair, or null when not curated.
IdTypeConfig? curatedIdType(String country, String key) {
  for (final c in curatedIdTypesForCountry(country)) {
    if (c.key == key) return c;
  }
  return null;
}

/// Title-cases a raw server ID key for a synthesized label, e.g.
/// `national-id` → `National Id`, `residence_permit` → `Residence Permit`.
String humanizeIdType(String key) {
  final words = key.replaceAll(RegExp(r'[-_]+'), ' ').trim().split(' ');
  return words
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Resolves the definition for a (country, key) pair: a curated entry wins;
/// otherwise a definition is synthesized from the server config row's metadata
/// (label / requiresDocumentCapture / scanSides / supportsNfc). Document capture
/// defaults on for synthesized types (the safe assumption for an unknown
/// document ID); the row's flags narrow it. Mirrors the web SDK resolver.
IdTypeConfig resolveIdTypeDefinition(
  String country,
  String key, {
  String? label,
  bool? requiresDocumentCapture,
  String? scanSides,
  bool? supportsNfc,
}) {
  final curated = curatedIdType(country, key);
  if (curated != null) return curated;

  final needsCapture = requiresDocumentCapture ?? true;
  return IdTypeConfig(
    key: key,
    label: (label != null && label.isNotEmpty) ? label : humanizeIdType(key),
    requiresDocumentCapture: needsCapture,
    scanSides: needsCapture
        ? (parseScanSides(scanSides) ?? ScanSides.frontOnly)
        : null,
    supportsNfc: supportsNfc ?? false,
  );
}
