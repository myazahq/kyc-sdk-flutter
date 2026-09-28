import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../config/theme.dart';
import '../config/trust_attribution.dart';
import '../providers/kyc_provider.dart';

/// The consent notice's lead-in when the org's own logo replaces Myaza's in
/// the footer: Myaza still processes the applicant's data (and biometrics), so
/// the notice names it as the provider for that organisation. Null when the
/// footer is Myaza's own. Not customisable, on any SDK.
String? consentMyazaLead(
  SdkTrustAttribution? attribution, {
  String? workflowCompanyName,
  String? brandingCompanyName,
}) {
  if (!needsMyazaDisclosure(attribution)) return null;
  final org = myazaProviderName(
      attribution, workflowCompanyName, brandingCompanyName);
  return org.isEmpty
      ? 'Verification is processed by Myaza Trust.'
      : 'Verification is processed by Myaza Trust for $org.';
}

/// The consent notice above Continue, one paragraph. Consent is given by
/// ACTING, so it sits right above the button it describes. The biometric
/// sentence is derived from what the flow does: claiming facial recognition
/// with no selfie step would be false, and recording video without saying so
/// is the failure that actually matters. None of it is customisable.
class ConsentLegalNotice extends ConsumerStatefulWidget {
  const ConsentLegalNotice({
    super.key,
    required this.isBusiness,
    required this.capturesFace,
    required this.recordsVideo,
  });

  final bool isBusiness;
  final bool capturesFace;
  final bool recordsVideo;

  @override
  ConsumerState<ConsentLegalNotice> createState() => _ConsentLegalNoticeState();
}

class _ConsentLegalNoticeState extends ConsumerState<ConsentLegalNotice> {
  // One recognizer per link, owned by the State so they can be disposed.
  // Building them inline in `build` leaks a recognizer on every rebuild.
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _open(kTermsUrl);
    _privacyTap = TapGestureRecognizer()..onTap = () => _open(kPrivacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  /// A failure is swallowed: not being able to show the terms must never
  /// block someone from verifying, and there is no recovery to offer mid-flow.
  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // no-op
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final config = ref.watch(kycConfigProvider);
    final branding =
        ref.watch(kYCNotifierProvider.select((s) => s.serverConfig.branding));
    final attribution = branding?.trustAttribution;
    final lead = consentMyazaLead(
      attribution,
      // The appearance's built-in default is Myaza's own name, not the org's.
      workflowCompanyName: config.appearance?.companyName == 'Myaza'
          ? null
          : config.appearance?.companyName,
      brandingCompanyName: branding?.companyName,
    );
    final myazaTerms = lead != null;
    // Web: `font-medium text-foreground underline`, as RN draws.
    final linkStyle = TextStyle(
      color: colors.textDark,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: colors.textDark,
    );

    return Text.rich(
      TextSpan(
        style: text.bodySmall,
        children: [
          if (lead != null) TextSpan(text: '$lead '),
          TextSpan(
            text: myazaTerms
                ? 'By tapping Continue, you agree to Myaza Trust’s '
                : 'By tapping Continue, you agree to the ',
          ),
          TextSpan(
              text: 'End User Terms', style: linkStyle, recognizer: _termsTap),
          const TextSpan(text: ' and '),
          TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: _privacyTap),
          TextSpan(
            text: widget.isBusiness
                ? ', and consent to your business and personal data being '
                    'processed to verify your identity.'
                : ', and consent to your personal data being processed to '
                    'verify your identity.',
          ),
          if (widget.capturesFace)
            const TextSpan(
              text:
                  ' This includes facial recognition and recording this session.',
            )
          else if (widget.recordsVideo)
            const TextSpan(text: ' This includes recording this session.'),
        ],
      ),
    );
  }
}
