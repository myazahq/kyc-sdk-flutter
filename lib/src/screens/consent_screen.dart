import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
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

/// Replaces `{firstName}` / `{lastName}` tokens with the user's data (or '').
String _fillTokens(String template, String firstName, String lastName) =>
    template
        .replaceAll('{firstName}', firstName)
        .replaceAll('{lastName}', lastName)
        .trim();

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final config = ref.watch(kycConfigProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final firstName = config.userData?.firstName ?? '';
    final lastName = config.userData?.lastName ?? '';

    final defaultTitle =
        firstName.isNotEmpty ? 'Welcome, $firstName' : 'Identity Verification';
    final title = config.consent?.title != null
        ? _fillTokens(config.consent!.title!, firstName, lastName)
        : defaultTitle;
    final description = config.consent?.description != null
        ? _fillTokens(config.consent!.description!, firstName, lastName)
        : _kDefaultConsentDescription;

    // Reflect the actually-enabled features so the list matches the real flow.
    // Same lucide icons as the web SDK's ConsentStep.
    final steps = <_ProcessStep>[
      const _ProcessStep(
        LucideIcons.badgeCheck,
        'Verify your government-issued ID',
      ),
      const _ProcessStep(
        LucideIcons.userRound,
        'Collect basic personal information',
      ),
      if (config.enableDocumentCapture)
        const _ProcessStep(
          LucideIcons.scanLine,
          'Capture a photo of your ID document',
        ),
      if (config.enableSelfie)
        const _ProcessStep(
          LucideIcons.scanFace,
          'Take a selfie for facial verification',
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

        // ── Consent checkbox ─────────────────────────────────────────────────
        _ConsentCheckbox(
          value: _agreed,
          colors: colors,
          text: text,
          onChanged: (v) => setState(() => _agreed = v),
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Continue ─────────────────────────────────────────────────────────
        MyazaButton(
          label: 'Continue',
          onPressed: _agreed ? notifier.nextStep : null,
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

// ─── Consent checkbox ─────────────────────────────────────────────────────────

class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final MyazaColorScheme colors;
  final MyazaThemeText text;
  final ValueChanged<bool> onChanged;

  const _ConsentCheckbox({
    required this.value,
    required this.colors,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(MyazaSpacing.md),
        decoration: BoxDecoration(
          color: value
              ? colors.primary.withValues(alpha: 0.06)
              : colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(MyazaRadius.xs - 2),
                  border: Border.all(
                    color: value ? colors.primary : colors.gray400,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? Icon(Icons.check_rounded, size: 14, color: colors.onPrimary)
                    : null,
              ),
            ),
            const SizedBox(width: MyazaSpacing.sm + 2),
            Expanded(
              child: Text(
                'I consent to the collection and processing of my personal data '
                'for identity verification purposes.',
                style: text.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
