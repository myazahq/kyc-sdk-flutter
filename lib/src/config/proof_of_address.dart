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
  other;

  /// Stable server key (submitted as `proofOfAddressType`).
  String get key => switch (this) {
        PoaDocumentType.utilityBill => 'utility_bill',
        PoaDocumentType.bankStatement => 'bank_statement',
        PoaDocumentType.tenancyAgreement => 'tenancy_agreement',
        PoaDocumentType.other => 'other',
      };

  String get label => switch (this) {
        PoaDocumentType.utilityBill => 'Utility bill',
        PoaDocumentType.bankStatement => 'Bank statement',
        PoaDocumentType.tenancyAgreement => 'Tenancy agreement',
        PoaDocumentType.other => 'Other document',
      };

  static PoaDocumentType fromKey(String key) => switch (key) {
        'utility_bill' => PoaDocumentType.utilityBill,
        'bank_statement' => PoaDocumentType.bankStatement,
        'tenancy_agreement' => PoaDocumentType.tenancyAgreement,
        _ => PoaDocumentType.other,
      };
}

class ProofOfAddressConfig {
  final bool enabled;

  /// Offered document-type keys (empty = all four).
  final List<String> documentTypes;

  /// Max document age the server enforces (soft). Shown to the user.
  final int maxAgeDays;

  const ProofOfAddressConfig({
    this.enabled = false,
    this.documentTypes = const [],
    this.maxAgeDays = 90,
  });

  /// The document types to offer, resolved to the enum (all four when unset).
  List<PoaDocumentType> get offeredTypes {
    if (documentTypes.isEmpty) return PoaDocumentType.values;
    return documentTypes.map(PoaDocumentType.fromKey).toList(growable: false);
  }

  factory ProofOfAddressConfig.fromJson(Map<String, dynamic> json) =>
      ProofOfAddressConfig(
        enabled: json['enabled'] as bool? ?? false,
        documentTypes: ((json['documentTypes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        maxAgeDays: (json['maxAgeDays'] as num?)?.toInt() ?? 90,
      );
}
