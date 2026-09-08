// ─── Proof of Address config ──────────────────────────────────────────────────
//
// Collects a proof-of-address document (utility bill / bank statement / tenancy,
// image or PDF) after capture. The check is a SOFT sub-result server-side (it
// never changes the verification's own status). Mirrors the web SDK's
// ProofOfAddressConfig. Document-type keys are a stable contract.

enum PoaDocumentType {
  utilityBill,
  bankStatement,
  tenancyAgreement,
  governmentDocument,
  other;

  /// Stable server key (submitted as `proofOfAddressType`).
  String get key => switch (this) {
        PoaDocumentType.utilityBill => 'utility_bill',
        PoaDocumentType.bankStatement => 'bank_statement',
        PoaDocumentType.tenancyAgreement => 'tenancy_agreement',
        PoaDocumentType.governmentDocument => 'government_document',
        PoaDocumentType.other => 'other',
      };

  String get label => switch (this) {
        PoaDocumentType.utilityBill => 'Utility bill',
        PoaDocumentType.bankStatement => 'Bank statement',
        PoaDocumentType.tenancyAgreement => 'Tenancy agreement',
        PoaDocumentType.governmentDocument => 'Government-issued document',
        PoaDocumentType.other => 'Other document',
      };

  /// The kind for a server key, or null for one THIS build does not know —
  /// a newer kind the dashboard offers before the SDK ships is hidden from the
  /// picker rather than drawn as a second "Other document" (the web/RN rule).
  static PoaDocumentType? tryFromKey(String key) => switch (key) {
        'utility_bill' => PoaDocumentType.utilityBill,
        'bank_statement' => PoaDocumentType.bankStatement,
        'tenancy_agreement' => PoaDocumentType.tenancyAgreement,
        'government_document' => PoaDocumentType.governmentDocument,
        'other' => PoaDocumentType.other,
        _ => null,
      };

  static PoaDocumentType fromKey(String key) =>
      tryFromKey(key) ?? PoaDocumentType.other;
}

/// Whether the applicant's name must appear on the document. The SERVER
/// judges this; the SDK reads it only to word the step (under `off` the header
/// asks for a document that shows the address, not the name).
enum PoaNameRule {
  required,
  optional,
  off;

  static PoaNameRule? tryFromKey(Object? key) => switch (key) {
        'required' => PoaNameRule.required,
        'optional' => PoaNameRule.optional,
        'off' => PoaNameRule.off,
        _ => null,
      };
}

class ProofOfAddressConfig {
  final bool enabled;

  /// Offered document-type keys (empty = all four).
  final List<String> documentTypes;

  /// Max document age the server enforces (soft). Shown to the user.
  final int maxAgeDays;

  /// Org-supplied name for the `other` kind (e.g. "Council tax letter"), set in
  /// the workflow builder. Null/blank keeps the generic label.
  final String? otherLabel;

  /// The org's accepted countries, upper-cased (empty = all). On the ADDRESS
  /// SCOPE this is exactly what the declared-country picker offers; on a full
  /// flow it gates the step client-side (the server stays soft).
  final List<String> countries;

  /// Per-country document-kind overrides (ISO-2 → kind keys). A present entry
  /// REPLACES [documentTypes] for that country.
  final Map<String, List<String>> countryDocuments;

  /// The default name rule for every country and kind (null = required).
  final PoaNameRule? nameMatch;

  /// Per-country, per-kind exceptions to [nameMatch] (ISO-2 → kind key → rule).
  final Map<String, Map<String, PoaNameRule>> countryNameMatch;

  const ProofOfAddressConfig({
    this.enabled = false,
    this.documentTypes = const [],
    this.maxAgeDays = 90,
    this.otherLabel,
    this.countries = const [],
    this.countryDocuments = const {},
    this.nameMatch,
    this.countryNameMatch = const {},
  });

  static List<PoaDocumentType> _known(List<String> keys) => keys
      .map(PoaDocumentType.tryFromKey)
      .whereType<PoaDocumentType>()
      .toList(growable: false);

  /// The document types to offer, resolved to the enum (every kind when unset,
  /// and when the list names only kinds this build does not know).
  List<PoaDocumentType> get offeredTypes {
    final known = _known(documentTypes);
    return known.isEmpty ? PoaDocumentType.values : known;
  }

  /// The kinds on offer for [country] (mirror of the web SDK's
  /// `poaOfferedKinds` — keep the three in lockstep): that country's override
  /// when the workflow declares one, else [offeredTypes].
  List<PoaDocumentType> offeredTypesFor(String? country) {
    final override =
        country == null ? null : countryDocuments[country.toUpperCase()];
    if (override != null) {
      final known = _known(override);
      if (known.isNotEmpty) return known;
    }
    return offeredTypes;
  }

  /// The name rule the server judges THIS document under — the country's
  /// per-kind exception, else the workflow default, else required. Mirror of
  /// the web SDK's `poaNamePolicy` and the server's `resolvePoaNamePolicy` —
  /// keep in lockstep. Read only to word the step.
  PoaNameRule namePolicyFor(String? country, PoaDocumentType? type) {
    final exception = country == null || type == null
        ? null
        : countryNameMatch[country.toUpperCase()]?[type.key];
    return exception ?? nameMatch ?? PoaNameRule.required;
  }

  /// Whether the accepted-country list admits [country]. An empty list accepts
  /// everyone; an unknown country is not refused here (the server is the gate).
  bool countryAccepted(String? country) {
    if (countries.isEmpty || country == null) return true;
    return countries.contains(country.toUpperCase());
  }

  /// Display label for [type], honouring the org's rename of `other`.
  String labelFor(PoaDocumentType type) {
    final custom = otherLabel?.trim();
    if (type == PoaDocumentType.other && custom != null && custom.isNotEmpty) {
      return custom;
    }
    return type.label;
  }

  factory ProofOfAddressConfig.fromJson(Map<String, dynamic> json) =>
      ProofOfAddressConfig(
        enabled: json['enabled'] as bool? ?? false,
        documentTypes: ((json['documentTypes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        maxAgeDays: (json['maxAgeDays'] as num?)?.toInt() ?? 90,
        otherLabel: json['otherLabel']?.toString(),
        countries: ((json['countries'] as List?) ?? const [])
            .map((e) => e.toString().toUpperCase())
            .toList(growable: false),
        countryDocuments: {
          for (final e in ((json['countryDocuments'] as Map?) ?? const {}).entries)
            e.key.toString().toUpperCase(): ((e.value as List?) ?? const [])
                .map((k) => k.toString())
                .toList(growable: false),
        },
        nameMatch: PoaNameRule.tryFromKey(json['nameMatch']),
        countryNameMatch: {
          for (final e in ((json['countryNameMatch'] as Map?) ?? const {}).entries)
            e.key.toString().toUpperCase(): {
              for (final k in ((e.value as Map?) ?? const {}).entries)
                if (PoaNameRule.tryFromKey(k.value) != null)
                  k.key.toString(): PoaNameRule.tryFromKey(k.value)!,
            },
        },
      );
}
