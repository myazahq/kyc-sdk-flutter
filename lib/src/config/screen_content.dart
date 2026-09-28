// ─── Consent and success screen content ──────────────────────────────────────
//
// Split from kyc_config.dart (200-line rule); re-exported from there.

/// Overrides for the consent (welcome) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [MyazaKYCConfig.userData] (empty string when absent).
class KYCConsentContent {
  /// Heading. Defaults to `Welcome, {firstName}` when a first name is known,
  /// otherwise `Identity Verification`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in regulatory copy.
  final String? description;

  const KYCConsentContent({this.title, this.description});

  factory KYCConsentContent.fromJson(Map<String, dynamic> json) =>
      KYCConsentContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

// ─── Success screen content ──────────────────────────────────────────────────

/// Overrides for the success (submitted) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [MyazaKYCConfig.userData] (empty string when absent).
class KYCSuccessContent {
  /// Heading. Defaults to `Verification Submitted!`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in "submitted for
  /// review" copy.
  final String? description;

  const KYCSuccessContent({this.title, this.description});

  factory KYCSuccessContent.fromJson(Map<String, dynamic> json) =>
      KYCSuccessContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}
