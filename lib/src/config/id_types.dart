// ─── Country enum ────────────────────────────────────────────────────────────

// ignore_for_file: constant_identifier_names
enum Country {
  NG,
  GH,
  KE,
  ZA,
  CI;

  String get label => switch (this) {
        Country.NG => 'Nigeria',
        Country.GH => 'Ghana',
        Country.KE => 'Kenya',
        Country.ZA => 'South Africa',
        Country.CI => "Côte d'Ivoire",
      };
}

// ─── ID type enum ─────────────────────────────────────────────────────────────

enum IdType {
  bvn,
  bvnPremium,
  taxId,
  nin,
  vnin,
  passport,
  driversLicense,
  pvc,
  ghanaCard,
  voters,
  ssnit,
  nationalId,
  cni,
  residenceCard;
}

// ─── Scan sides ───────────────────────────────────────────────────────────────

enum ScanSides {
  frontOnly,
  frontAndBack;
}

// ─── ID type config ───────────────────────────────────────────────────────────

class IdTypeConfig {
  final IdType idType;
  final String key;
  final String label;

  /// What the user actually types when it differs from the ID's name — e.g.
  /// Tax ID lookups are keyed off the person's NIN, so the input asks for a NIN.
  final String? inputLabel;
  final bool requiresDocumentCapture;
  final ScanSides? scanSides;
  final int? digits;
  final RegExp? pattern;

  const IdTypeConfig({
    required this.idType,
    required this.key,
    required this.label,
    this.inputLabel,
    required this.requiresDocumentCapture,
    this.scanSides,
    this.digits,
    this.pattern,
  });
}

// ─── ID types by country ──────────────────────────────────────────────────────

const Map<Country, List<IdTypeConfig>> kIdTypesByCountry = {
  Country.NG: [
    IdTypeConfig(
      idType: IdType.bvn,
      key: 'bvn',
      label: 'BVN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      idType: IdType.bvnPremium,
      key: 'bvn-premium',
      label: 'BVN Premium',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      idType: IdType.taxId,
      key: 'tax-id',
      label: 'Tax ID',
      inputLabel: 'NIN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      idType: IdType.nin,
      key: 'nin',
      label: 'NIN',
      requiresDocumentCapture: false,
      digits: 11,
    ),
    IdTypeConfig(
      idType: IdType.vnin,
      key: 'vnin',
      label: 'vNIN',
      requiresDocumentCapture: false,
      digits: 16,
    ),
    IdTypeConfig(
      idType: IdType.passport,
      key: 'passport',
      label: 'International Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
    ),
    IdTypeConfig(
      idType: IdType.driversLicense,
      key: 'drivers-license',
      label: "Driver's License",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.pvc,
      key: 'pvc',
      label: "Voter's Card",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
  Country.GH: [
    IdTypeConfig(
      idType: IdType.ghanaCard,
      key: 'ghana-card',
      label: 'Ghana Card',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.voters,
      key: 'voters',
      label: "Voter's Card",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.driversLicense,
      key: 'drivers-license',
      label: "Driver's License",
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.ssnit,
      key: 'ssnit',
      label: 'SSNIT',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
    ),
    IdTypeConfig(
      idType: IdType.passport,
      key: 'passport',
      label: 'Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
    ),
  ],
  Country.KE: [
    IdTypeConfig(
      idType: IdType.nationalId,
      key: 'national-id',
      label: 'National ID',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.passport,
      key: 'passport',
      label: 'Passport',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontOnly,
    ),
  ],
  Country.ZA: [
    IdTypeConfig(
      idType: IdType.nationalId,
      key: 'national-id',
      label: 'National ID',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
  Country.CI: [
    IdTypeConfig(
      idType: IdType.cni,
      key: 'cni',
      label: 'CNI',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
    IdTypeConfig(
      idType: IdType.residenceCard,
      key: 'residence-card',
      label: 'Residence Card',
      requiresDocumentCapture: true,
      scanSides: ScanSides.frontAndBack,
    ),
  ],
};

/// Returns all [IdTypeConfig]s for the given [country], optionally filtered
/// to only those whose [IdType] is in [allowedTypes].
List<IdTypeConfig> getIdTypesForCountry(
  Country country, {
  List<IdType>? allowedTypes,
}) {
  final all = kIdTypesByCountry[country] ?? [];
  if (allowedTypes == null) return all;
  return all.where((c) => allowedTypes.contains(c.idType)).toList();
}

/// Looks up the [IdTypeConfig] for a given [country] and [idType].
/// Returns null if the combination is not supported.
IdTypeConfig? getIdTypeConfig(Country country, IdType idType) {
  final configs = kIdTypesByCountry[country] ?? [];
  try {
    return configs.firstWhere((c) => c.idType == idType);
  } catch (_) {
    return null;
  }
}
