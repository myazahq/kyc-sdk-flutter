import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../widgets/myaza_button.dart';

// ─── Contact verification — footer actions ────────────────────────────────────
//
// The error line, the primary submit button, and the optional skip. Lifted out
// of ContactVerificationScreen when the delivery-channel picker joined it, to
// keep that file inside the 200-line limit.

class ContactActions extends StatelessWidget {
  /// Null when there is nothing to report.
  final String? error;

  /// Send-the-code vs verify-the-code: changes only the label and the handler.
  final bool hasChallenge;
  final bool isBusy;

  /// Null disables the button (invalid input, or a request in flight).
  final VoidCallback? onSubmit;

  /// Shown only for an optional step.
  final VoidCallback? onSkip;

  /// Drives the closing reassurance line, which differs per channel.
  final bool isPhone;

  const ContactActions({
    super.key,
    required this.error,
    required this.hasChallenge,
    required this.isBusy,
    required this.onSubmit,
    required this.onSkip,
    required this.isPhone,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Text(error!,
              style: text.bodySmall.copyWith(color: MyazaColors.error)),
        ],
        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: hasChallenge ? 'Verify code' : 'Send code',
          isLoading: isBusy,
          onPressed: onSubmit,
        ),
        if (onSkip != null) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Center(
            child: TextButton(
              onPressed: isBusy ? null : onSkip,
              child: Text('Skip for now',
                  style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            ),
          ),
        ],
        const SizedBox(height: MyazaSpacing.md),
        // Answers the question the step provokes: an email step is asked "what
        // will you do with my address", a phone step "will this cost me money".
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPhone ? LucideIcons.smartphone : LucideIcons.mail,
              size: 12,
              color: colors.textSecondary,
            ),
            const SizedBox(width: MyazaSpacing.xs),
            Flexible(
              child: Text(
                isPhone
                    ? 'Standard message rates may apply.'
                    : 'We only use this to verify your identity.',
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
