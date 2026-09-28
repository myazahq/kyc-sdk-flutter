import '../config/scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../config/business_application.dart';
import '../i18n/text_scope.dart';
import '../providers/step_resubmit.dart';
import 'consent_legal_notice.dart';
import 'consent_process_steps.dart';
import '../providers/kyc_provider.dart';
import '../widgets/myaza_button.dart';
import '../widgets/icons/icons.dart';

// ─── Consent screen ───────────────────────────────────────────────────────────

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

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

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final config = ref.watch(kycConfigProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final firstName = config.userData?.firstName ?? '';
    final isBusiness = config.subjectType == 'business';
    final scope = isBusiness ? null : configScope(config.scope);
    final faceScope = isFaceScope(scope);
    final business = config.business;

    // The shared copy is a catalogue text; the named, business and scope
    // variants keep this SDK's wording. An older consent.title/description
    // (tokens filled) wins over every variant, as it always did.
    final t = ref.watch(kycTextProvider);
    final variantTitle = firstName.isNotEmpty
        ? 'Welcome, {firstName}'
        : isBusiness
            ? 'Business Verification'
            : _kScopeTitles[scope];
    final title = t(variantTitle == null ? 'welcome.title' : 'welcome.title.variant',
        legacy: config.consent?.title, fallback: variantTitle);
    final variantDescription = isBusiness
        ? _kDefaultBusinessConsentDescription
        : _kScopeDescriptions[scope];
    final description = t(
        variantDescription == null
            ? 'welcome.description'
            : 'welcome.description.variant',
        legacy: config.consent?.description,
        fallback: variantDescription);

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

    final steps = consentProcessSteps(config,
        isBusiness: isBusiness, scope: scope, t: t);

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
                const MyazaIcon(MyazaIcons.refreshCw, size: 16, color: MyazaColors.warning),
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
        _ProcessStepsCard(
          colors: colors,
          text: text,
          heading: t('welcome.process.heading').toUpperCase(),
          steps: steps,
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Consent notice ───────────────────────────────────────────────────
        // Consent is given by ACTING now, so the notice sits immediately above
        // the button it describes — adjacency is what makes it informed. The
        // biometric sentence is DERIVED: claiming facial recognition on a flow
        // with no selfie step would be false, and recording video without
        // saying so is the failure that actually matters.
        ConsentLegalNotice(
          isBusiness: isBusiness,
          capturesFace: capturesFace,
          recordsVideo: recordsVideo,
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Continue ─────────────────────────────────────────────────────────
        MyazaButton(
          label: t('common.continue'),
          onPressed: notifier.nextStep,
        ),
        const SizedBox(height: MyazaSpacing.sm),

        // ── Reassurance footer ───────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MyazaIcon(MyazaIcons.lock, size: 13, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(t('welcome.secureNote'), style: text.bodySmall),
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
            child: MyazaIcon(MyazaIcons.shieldCheck, size: 28, color: colors.onPrimary),
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
  final String heading;
  final List<ConsentProcessStep> steps;

  const _ProcessStepsCard({
    required this.colors,
    required this.text,
    required this.heading,
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
            heading,
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
  final ConsentProcessStep step;
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
          child: MyazaIcon(step.icon, size: 18, color: colors.primary),
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
