import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import '../config/kyc_config.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/myaza_button.dart';

// ─── Error view ───────────────────────────────────────────────────────────────

class ErrorView extends StatelessWidget {
  final KYCError error;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  const ErrorView({super.key, 
    required this.error,
    required this.onClose,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final title = switch (error.code) {
      'insufficient_credits' => 'Credits Exhausted',
      'invalid_api_key' => 'Authentication Failed',
      'feature_disabled' => 'Verification Unavailable',
      'invalid_workflow' => 'Verification Unavailable',
      'upload_failed' => 'Upload Failed',
      'network_error' => 'Connection Failed',
      'invalid_state' => 'Submission Incomplete',
      _ => 'Submission Failed',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: MyazaSpacing.xl),
            Center(
              child: _ErrorBadge(colors: colors)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 450.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              title,
              style: text.heading1,
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: MyazaSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
              child: MyazaAlert(
                variant: MyazaAlertVariant.error,
                title: 'What happened',
                message: error.message,
              ),
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
          ],
        ),
        Row(
          children: [
            if (onRetry != null) ...[
              Expanded(
                child: MyazaButton.outline(
                  label: 'Try Again',
                  onPressed: onRetry,
                  leadingIcon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(width: MyazaSpacing.md),
            ],
            Expanded(
              child: MyazaButton(label: 'Close', onPressed: onClose),
            ),
          ],
        )
            .animate(delay: 420.ms)
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, end: 0, duration: 300.ms),
      ],
    );
  }
}

// ─── Check badge ──────────────────────────────────────────────────────────────
class _ErrorBadge extends StatelessWidget {
  final MyazaColorScheme colors;

  const _ErrorBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.errorBg,
        border: Border.all(
          color: MyazaColors.error.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.error_outline_rounded,
        size: 44,
        color: MyazaColors.error,
      ),
    );
  }
}
