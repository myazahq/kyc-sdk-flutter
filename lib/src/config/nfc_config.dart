// ─── NFC chip config ──────────────────────────────────────────────────────────
//
// eMRTD (ICAO 9303) chip verification for chip-capable documents (passports
// everywhere, plus curated chip cards like the Ghana Card and CI CNI). The SDK
// reads DG1 + EF.SOD off the chip and submits them; passive authentication runs
// SERVER-SIDE (client authenticity claims are never trusted). A SOFT sub-result
// — it never changes the verification's own status. Mirrors the web SDK's
// `WorkflowConfigSchema.nfc` (web is preview-only; the mobile SDKs own the real
// step). A resolved workflow is AUTHORITATIVE for enabled/idTypes.

class NfcConfig {
  final bool enabled;

  /// Which chip-capable IDs run the chip step, as `"CC/idType"` composite keys
  /// (e.g. `["NG/passport", "GH/ghana-card"]`). Null/empty = all chip-capable.
  final List<String>? idTypes;

  /// Show a manual "my device can't scan the chip — skip" affordance. (Devices
  /// with no NFC radio auto-skip regardless.)
  final bool allowSkip;

  const NfcConfig({
    this.enabled = false,
    this.idTypes,
    this.allowSkip = false,
  });

  /// Whether NFC applies to (country, idKey). The caller first checks the ID is
  /// chip-capable (`IdTypeConfig.supportsNfc`); this narrows by the workflow's
  /// composite-key selection (unset = all chip-capable IDs).
  bool selects(String country, String idKey) {
    final keys = idTypes;
    if (keys == null || keys.isEmpty) return true;
    final target = '${country.toUpperCase()}/$idKey';
    return keys.any((k) => k.toUpperCase() == target.toUpperCase());
  }

  factory NfcConfig.fromJson(Map<String, dynamic> json) => NfcConfig(
        enabled: json['enabled'] as bool? ?? false,
        idTypes: (json['idTypes'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false),
        allowSkip: json['allowSkip'] as bool? ?? false,
      );
}
