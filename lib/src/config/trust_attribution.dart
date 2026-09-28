// ─── Footer attribution ───────────────────────────────────────────────────────
//
// Which attribution the footer draws, resolved SERVER-side from the published
// workflow (`branding.trustAttribution`): the Myaza Trust lockup (the default,
// and what an older server that sends nothing means), or the organisation's
// own logo with no Myaza mark at all. A port of the web SDK's
// trust-attribution-resolve.ts and lib/trust-attribution.ts.

/// The server's answer, read defensively: config JSON can come from an older
/// or mixed-version server.
class SdkTrustAttribution {
  /// `'custom'` or `'myaza'`. Anything else was parsed as Myaza.
  final String mode;
  final String? logo;

  /// The org's dark-theme version of [logo], for a flow on its dark theme.
  final String? logoDark;
  final String? companyName;

  const SdkTrustAttribution.myaza()
      : mode = 'myaza',
        logo = null,
        logoDark = null,
        companyName = null;

  const SdkTrustAttribution.custom({this.logo, this.logoDark, this.companyName})
      : mode = 'custom';

  bool get isCustom => mode == 'custom';

  /// Anything that is not `custom` is Myaza, a missing or malformed block
  /// included. A `custom` with a malformed logo STAYS custom: falling back to
  /// Myaza would put our mark on a flow the org asked to carry their own.
  factory SdkTrustAttribution.fromJson(Object? raw) {
    if (raw is! Map || raw['mode'] != 'custom') {
      return const SdkTrustAttribution.myaza();
    }
    return SdkTrustAttribution.custom(
      logo: _text(raw['logo']),
      logoDark: _text(raw['logoDark']),
      companyName: _text(raw['companyName']),
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// What the footer draws for [attribution] on a flow that is [dark] or not.
class ResolvedTrustAttribution {
  final bool custom;

  /// The logo to draw (the dark-theme one on a dark flow when supplied).
  final String? logo;
  final String? companyName;

  const ResolvedTrustAttribution({
    required this.custom,
    this.logo,
    this.companyName,
  });
}

ResolvedTrustAttribution resolveTrustAttribution(
  SdkTrustAttribution? attribution, {
  bool dark = false,
}) {
  if (attribution == null || !attribution.isCustom) {
    return const ResolvedTrustAttribution(custom: false);
  }
  return ResolvedTrustAttribution(
    custom: true,
    logo: (dark ? attribution.logoDark : null) ?? attribution.logo,
    companyName: attribution.companyName,
  );
}

/// Whether the consent screen must name Myaza. When an org's own logo
/// replaces Myaza's in the footer, Myaza still processes the applicant's data,
/// so the consent notice keeps it disclosed with a link to its terms.
bool needsMyazaDisclosure(SdkTrustAttribution? attribution) =>
    attribution?.isCustom ?? false;

/// The organisation Myaza provides the verification for, as the consent notice
/// names it: the name on the custom attribution, then the workflow's company
/// name, then the branding name. '' when none is known.
String myazaProviderName(
  SdkTrustAttribution? attribution,
  String? workflowCompanyName,
  String? brandingCompanyName,
) {
  final custom = attribution?.isCustom ?? false ? attribution!.companyName : null;
  for (final name in [custom, workflowCompanyName, brandingCompanyName]) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '';
}
