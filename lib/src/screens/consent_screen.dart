import 'package:flutter/gestures.dart';
import '../config/scope.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../config/brand.dart';
import '../config/business_application.dart';
import '../providers/step_resubmit.dart';
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

const Map<String, String> _kScopeTitles = {
  'address': 'Address Verification',
  'biometric-authentication': 'Face Check',
  'biometric-enrollment': 'Face Enrolment',
  'questionnaire': 'A Few Questions',
  'contact': 'Confirm Your Contact Details',
};

const Map<String, String> _kScopeDescriptions = {
  'address':
      'We need to confirm your home address to comply with regulatory requirements. This process is quick and secure.',
  'biometric-authentication':
      'A quick face check confirms it is really you. This takes a few seconds and is secure.',
  'biometric-enrollment':
      'A quick selfie sets up face checks for next time, so you will not have to prove your identity again. This takes a few seconds and is secure.',
  'questionnaire':
      'A few questions keep your account details up to date and help us comply with regulatory requirements.',
  'contact':
      'We need to re-confirm the email address and phone number on your account. This takes a minute and is secure.',
};

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
    final scope = isBusiness ? null : configScope(config.scope);
    final faceScope = isFaceScope(scope);
    final business = config.business;

    final defaultTitle = firstName.isNotEmpty
        ? 'Welcome, $firstName'
        : isBusiness
            ? 'Business Verification'
            : _kScopeTitles[scope] ?? 'Identity Verification';
    final title = config.consent?.title != null
        ? _fillTokens(config.consent!.title!, firstName, lastName, businessName)
        : defaultTitle;
    final description = config.consent?.description != null
        ? _fillTokens(
            config.consent!.description!, firstName, lastName, businessName)
        : isBusiness
            ? _kDefaultBusinessConsentDescription
            : _kScopeDescriptions[scope] ?? _kDefaultConsentDescription;

    // Reflect the actually-enabled features so the list matches the real flow.
    // Same lucide icons as the web SDK's ConsentStep.
    // What this flow ACTUALLY does — the notice must not overclaim
    // (facial recognition with no selfie step) or underclaim (recording
    // video without saying so, which is the one that carries risk). A business
    // flow captures a face only when the applicant verifies their own identity
    // in-flow; a pure registry lookup captures nothing.
    final capturesFace = isBusiness
        ? hasApplicantVerification(business)
        : faceScope || (scope == null && config.enableSelfie);
    final recordsVideo = capturesFace ||
        (!isBusiness && scope == null && config.enableDocumentCapture);

    final hasEmail = config.emailVerification?.enabled ?? false;
    final hasPhone = config.phoneVerification?.enabled ?? false;
    final hasContactStep = hasEmail || hasPhone;
    final contactWhat = hasEmail && hasPhone
        ? 'email and phone number'
        : hasEmail
            ? 'email'
            : 'phone number';

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
      ] else if (scope == 'address') ...[
        // NOT a fixed pair: the scope verifies an address by the pin, by a
        // document, or by both, so promising a map on a flow that only asks
        // for a document is a promise the flow never keeps. The document's own
        // bullet is appended by the shared post-capture block below.
        if (config.addressCollection?.enabled ?? false) ...[
          const _ProcessStep(
            LucideIcons.mapPinHouse,
            'Pin your home address on a map',
          ),
          const _ProcessStep(
            LucideIcons.badgeCheck,
            'Confirm the details only you can know',
          ),
        ],
      ] else if (faceScope) ...[
        const _ProcessStep(
          LucideIcons.scanFace,
          'Take a quick selfie with liveness checks',
        ),
        _ProcessStep(
          LucideIcons.badgeCheck,
          scope == 'biometric-authentication'
              ? 'We match it against your enrolled face'
              : 'It becomes your face check for next time',
        ),
      ] else if (scope == 'questionnaire') ...[
        const _ProcessStep(
          LucideIcons.badgeCheck,
          'Answer a few short questions',
        ),
      ] else if (scope == 'contact') ...[
        const _ProcessStep(
          LucideIcons.lock,
          'Confirm your contact details with a one-time code',
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
      // On the CONTACT scope the catalogue bullet already says this —
      // appending the generic line showed "confirm your contact details"
      // twice the moment both channels were on.
      if (scope != 'contact' && hasContactStep)
        _ProcessStep(
          LucideIcons.lock,
          'Confirm your $contactWhat with a one-time code',
        ),
      if (!isBusiness && scope == null && config.enableDocumentCapture)
        const _ProcessStep(
          LucideIcons.scanLine,
          'Capture a photo of your ID document',
        ),
      // Chip-capable IDs (e-passports, some eID cards) additionally read the
      // document's NFC chip. Shown when the flow enables NFC so the user knows
      // to have the physical document to hand — same "what may happen" spirit as
      // the document/selfie rows (a non-chip ID simply skips it).
      if (!isBusiness && scope == null && (config.nfc?.enabled ?? false))
        const _ProcessStep(
          LucideIcons.nfc,
          'Scan your document’s security chip (NFC)',
        ),
      if (!isBusiness && scope == null && config.enableSelfie)
        const _ProcessStep(
          LucideIcons.scanFace,
          'Take a selfie for facial verification',
        ),
      // Post-capture features, in the order the flow runs them. Each is gated
      // on the flow that actually asks for it, and skipped where a scope's own
      // catalogue bullet already covers the same step.
      if (!isBusiness && (config.proofOfAddress?.enabled ?? false))
        const _ProcessStep(
          LucideIcons.fileText,
          'Upload a proof of address document',
        ),
      if (scope != 'address' && (config.addressCollection?.enabled ?? false))
        const _ProcessStep(
          LucideIcons.mapPinHouse,
          'Pin your address on a map',
        ),
      // The step-order predicate, not a raw fields check: a questionnaire with
      // questions but enabled: false never runs, so it must not be promised.
      if (scope != 'questionnaire' && (config.questionnaire?.isActive ?? false))
        const _ProcessStep(
          LucideIcons.badgeCheck,
          'Answer a few short questions',
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

    // A reviewer sent this applicant back. Say so, and say why — the note is
    // the only thing on screen that explains a flow which has silently lost
    // most of its steps. Above the hero so it is read before the instructions.
    final redoNote = resubmitNote(config.resubmit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MyazaSpacing.sm),

        if (redoNote != null) ...[
          Container(
            padding: const EdgeInsets.all(MyazaSpacing.md),
            decoration: BoxDecoration(
              color: colors.warningBg,
              borderRadius: BorderRadius.circular(MyazaRadius.lg),
              border: Border.all(
                color: MyazaColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.refreshCw, size: 16, color: MyazaColors.warning),
                const SizedBox(width: MyazaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A few things to redo',
                        style: text.bodyMedium.copyWith(color: MyazaColors.warning),
                      ),
                      const SizedBox(height: 2),
                      Text(redoNote, style: text.bodySmall.copyWith(color: colors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyazaSpacing.lg),
        ],

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
                // Web: `font-medium text-foreground underline`, as RN draws.
                style: TextStyle(
                  color: colors.textDark,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.textDark,
                ),
                recognizer: _termsTap,
              ),
              const TextSpan(text: ' and '),
              TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(
                  color: colors.textDark,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.textDark,
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
            Icon(LucideIcons.lock, size: 13, color: colors.textMuted),
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
// Concentric tinted rings around a SOLID primary badge — mirrors the web
// SDK's consent hero (no gradients in the flow, house rule 2026-08-29).
// Recolors with the active primary color.

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
              color: colors.primary,
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
