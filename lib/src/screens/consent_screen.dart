import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../config/brand.dart';
import '../config/business_application.dart';
import '../providers/kyc_provider.dart';
import '../widgets/myaza_button.dart';

// ─── Consent screen ───────────────────────────────────────────────────────────

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ProcessStep {
  final IconData icon;
  final String label;
  const _ProcessStep(this.icon, this.label);
}

const String _kDefaultConsentDescription =
    'We need to verify your identity to comply with regulatory '
    'requirements. This process is quick and secure.';

const String _kDefaultBusinessConsentDescription =
    'We need to verify your business to comply with regulatory '
    'requirements. This process is quick and secure.';

/// Replaces `{firstName}` / `{lastName}` / `{businessName}` tokens with the
/// user's data (or ''). `{businessName}` is the KYB consent-copy token —
/// registration details aren't collected until after consent, so it resolves
/// only when the integrator passes it in via userData.
String _fillTokens(
  String template,
  String firstName,
  String lastName,
  String businessName,
) =>
    template
        .replaceAll('{firstName}', firstName)
        .replaceAll('{lastName}', lastName)
        .replaceAll('{businessName}', businessName)
        .trim();

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
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

  /// Opens in the platform browser. A failure is swallowed: not being able to
  /// show the terms must never block someone from verifying, and there is no
  /// useful recovery to offer them mid-flow.
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
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final firstName = config.userData?.firstName ?? '';
    final lastName = config.userData?.lastName ?? '';
    final businessName = config.userData?.businessName ?? '';
    final isBusiness = config.subjectType == 'business';
    final business = config.business;

    final defaultTitle = firstName.isNotEmpty
        ? 'Welcome, $firstName'
        : isBusiness
            ? 'Business Verification'
            : 'Identity Verification';
    final title = config.consent?.title != null
        ? _fillTokens(config.consent!.title!, firstName, lastName, businessName)
        : defaultTitle;
    final description = config.consent?.description != null
        ? _fillTokens(
            config.consent!.description!, firstName, lastName, businessName)
        : isBusiness
            ? _kDefaultBusinessConsentDescription
            : _kDefaultConsentDescription;

    // Reflect the actually-enabled features so the list matches the real flow.
    // Same lucide icons as the web SDK's ConsentStep.
    // What this flow ACTUALLY does — the notice must not overclaim
    // (facial recognition with no selfie step) or underclaim (recording
    // video without saying so, which is the one that carries risk). A business
    // flow captures a face only when the applicant verifies their own identity
    // in-flow; a pure registry lookup captures nothing.
    final capturesFace =
        isBusiness ? hasApplicantVerification(business) : config.enableSelfie;
    final recordsVideo =
        capturesFace || (!isBusiness && config.enableDocumentCapture);

    final hasContactStep = (config.emailVerification?.enabled ?? false) ||
        (config.phoneVerification?.enabled ?? false);

    // A KYB flow lists its application steps — never the identity rows, which
    // would claim steps a registry-lookup flow does not run.
    final steps = <_ProcessStep>[
      if (isBusiness) ...[
        const _ProcessStep(
          LucideIcons.building2,
          'Collect your business registration details',
        ),
        const _ProcessStep(
          LucideIcons.badgeCheck,
          'Verify your business against the official registry',
        ),
      ] else ...[
        const _ProcessStep(
          LucideIcons.badgeCheck,
          'Verify your government-issued ID',
        ),
        const _ProcessStep(
          LucideIcons.userRound,
          'Collect basic personal information',
        ),
      ],
      if (hasContactStep)
        const _ProcessStep(
          LucideIcons.lock,
          'Confirm your contact details with a one-time code',
        ),
      if (!isBusiness && config.enableDocumentCapture)
        const _ProcessStep(
          LucideIcons.scanLine,
          'Capture a photo of your ID document',
        ),
      // Chip-capable IDs (e-passports, some eID cards) additionally read the
      // document's NFC chip. Shown when the flow enables NFC so the user knows
      // to have the physical document to hand — same "what may happen" spirit as
      // the document/selfie rows (a non-chip ID simply skips it).
      if (!isBusiness && (config.nfc?.enabled ?? false))
        const _ProcessStep(
          LucideIcons.nfc,
          'Scan your document’s security chip (NFC)',
        ),
      if (!isBusiness && config.enableSelfie)
        const _ProcessStep(
          LucideIcons.scanFace,
          'Take a selfie for facial verification',
        ),
      if (isBusiness && hasKeyPeopleCollection(business))
        const _ProcessStep(
          LucideIcons.usersRound,
          "List the company's directors and owners",
        ),
      if (isBusiness && hasBusinessDocumentsStep(business))
        const _ProcessStep(
          LucideIcons.fileText,
          'Upload supporting business documents',
        ),
      if (isBusiness && hasApplicantVerification(business))
        const _ProcessStep(
          LucideIcons.scanFace,
          'Verify your own identity',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MyazaSpacing.sm),

        // ── Shield hero ──────────────────────────────────────────────────────
        Center(child: _ShieldHero(colors: colors)),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Welcome heading ──────────────────────────────────────────────────
        Text(
          title,
          style: text.heading1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.sm),
        Text(
          description,
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Process steps card ───────────────────────────────────────────────
        _ProcessStepsCard(colors: colors, text: text, steps: steps),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Consent notice ───────────────────────────────────────────────────
        // Consent is given by ACTING now, so the notice sits immediately above
        // the button it describes — adjacency is what makes it informed. The
        // biometric sentence is DERIVED: claiming facial recognition on a flow
        // with no selfie step would be false, and recording video without
        // saying so is the failure that actually matters.
        Text.rich(
          TextSpan(
            style: text.bodySmall,
            children: [
              const TextSpan(text: 'By tapping Continue, you agree to the '),
              TextSpan(
                text: 'End User Terms',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary,
                ),
                recognizer: _termsTap,
              ),
              const TextSpan(text: ' and '),
              TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary,
                ),
                recognizer: _privacyTap,
              ),
              TextSpan(
                text: isBusiness
                    ? ', and consent to your business and personal data being '
                        'processed to verify your identity.'
                    : ', and consent to your personal data being processed to '
                        'verify your identity.',
              ),
              if (capturesFace)
                const TextSpan(
                  text: ' This includes facial recognition and recording this session.',
                )
              else if (recordsVideo)
                const TextSpan(text: ' This includes recording this session.'),
            ],
          ),
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Continue ─────────────────────────────────────────────────────────
        MyazaButton(
          label: 'Continue',
          onPressed: notifier.nextStep,
        ),
        const SizedBox(height: MyazaSpacing.sm),

        // ── Reassurance footer ───────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              'Your data is encrypted and securely processed',
              style: text.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Shield hero ──────────────────────────────────────────────────────────────
//
// Concentric tinted rings around a gradient primary badge — mirrors the web
// SDK's consent hero. Recolors with the active primary color.

class _ShieldHero extends StatelessWidget {
  final MyazaColorScheme colors;

  const _ShieldHero({required this.colors});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.10),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.15),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary,
                  Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.7),
                    colors.background,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(LucideIcons.shieldCheck, size: 28, color: colors.onPrimary),
          ),
        ],
      ),
    );
  }
}

// ─── Process steps card ───────────────────────────────────────────────────────

class _ProcessStepsCard extends StatelessWidget {
  final MyazaColorScheme colors;
  final MyazaThemeText text;
  final List<_ProcessStep> steps;

  const _ProcessStepsCard({
    required this.colors,
    required this.text,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.lg),
      ),
      padding: const EdgeInsets.all(MyazaSpacing.md + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DURING THIS PROCESS WE WILL',
            style: text.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: MyazaSpacing.md),
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _StepRow(step: steps[i], colors: colors, text: text),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _ProcessStep step;
  final MyazaColorScheme colors;
  final MyazaThemeText text;

  const _StepRow({
    required this.step,
    required this.colors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(MyazaRadius.xs),
          ),
          child: Icon(step.icon, size: 18, color: colors.primary),
        ),
        const SizedBox(width: MyazaSpacing.sm + 4),
        Expanded(
          child: Text(
            step.label,
            style: text.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}
