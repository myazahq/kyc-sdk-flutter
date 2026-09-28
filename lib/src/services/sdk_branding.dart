import '../config/trust_attribution.dart';

export '../config/trust_attribution.dart' show SdkTrustAttribution;

/// Org branding returned by /api/kyc/config. Surfaced so the SDK can render the
/// org's own logo when the consumer sets `appearance.logo = 'default'`. `logo`
/// is an absolute, public URL (or null when the org has none configured).
class SdkConfigBranding {
  final String? logo;
  final String? companyName;
  final String? primaryColor;

  /// Server-resolved footer attribution. Missing on older servers, which
  /// means Myaza.
  final SdkTrustAttribution trustAttribution;

  const SdkConfigBranding({
    this.logo,
    this.companyName,
    this.primaryColor,
    this.trustAttribution = const SdkTrustAttribution.myaza(),
  });

  factory SdkConfigBranding.fromJson(Map<String, dynamic> json) =>
      SdkConfigBranding(
        logo: json['logo'] as String?,
        companyName: json['companyName'] as String?,
        primaryColor: json['primaryColor'] as String?,
        trustAttribution: SdkTrustAttribution.fromJson(json['trustAttribution']),
      );
}
