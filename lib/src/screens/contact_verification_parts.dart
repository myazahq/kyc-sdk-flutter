import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/contact_verification.dart';
import '../config/theme.dart';
import '../widgets/expiry_countdown.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';
import '../widgets/otp_input.dart';
import '../widgets/phone_number_input.dart';

// ─── Contact verification — presentational parts ──────────────────────────────
//
// The panels the contact step swaps between (destination entry → code entry →
// verified). Split out of contact_verification_screen.dart to keep both files
// inside the 200-line limit; the screen owns all state and API calls.

/// Shown once the channel already holds a proof token — the confirmation panel
/// plus the Continue action.
class ContactVerifiedView extends StatelessWidget {
  final bool isPhone;

  /// The verified address/number, when known — shown verbatim like the web SDK.
  final String? destination;

  final VoidCallback onContinue;

  const ContactVerifiedView({
    super.key,
    required this.isPhone,
    required this.onContinue,
    this.destination,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final what = isPhone ? 'phone number' : 'email';
    final label = (destination != null && destination!.isNotEmpty)
        ? '$destination is verified.'
        : 'Your $what is verified.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(MyazaSpacing.md),
          decoration: BoxDecoration(
            color: colors.primary50,
            borderRadius: BorderRadius.circular(MyazaRadius.md),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.circleCheck, color: colors.primary),
              const SizedBox(width: MyazaSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(label: 'Continue', onPressed: onContinue),
      ],
    );
  }
}

/// Destination entry — an email field or the E.164 phone input.
class ContactDestinationField extends StatelessWidget {
  final bool isPhone;
  final TextEditingController emailController;
  final String defaultCountry;
  final bool enabled;
  final ValueChanged<String> onEmailChanged;
  final void Function(String e164, bool isValid) onPhoneChanged;

  const ContactDestinationField({
    super.key,
    required this.isPhone,
    required this.emailController,
    required this.defaultCountry,
    required this.enabled,
    required this.onEmailChanged,
    required this.onPhoneChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(isPhone ? 'Phone number' : 'Email address', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        if (isPhone)
          PhoneNumberInput(
            defaultCountry: defaultCountry,
            onChanged: onPhoneChanged,
          )
        else
          MyazaInput(
            controller: emailController,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            readOnly: !enabled,
            onChanged: onEmailChanged,
          ),
      ],
    );
  }
}

/// Code entry — the OTP field plus the expiry hint and resend action.
class ContactCodePanel extends StatelessWidget {
  final String destination;
  final int codeLength;
  final OtpInputStyle style;
  final bool enabled;

  /// Remounts the OTP field (clearing typed digits) when the challenge changes,
  /// so a resend never leaves the previous code on screen.
  final String challengeId;

  /// When the code stops being valid — drives the live countdown. Null falls
  /// back to static copy.
  final DateTime? expiresAt;

  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final VoidCallback? onResend;

  const ContactCodePanel({
    super.key,
    required this.destination,
    required this.codeLength,
    required this.style,
    required this.enabled,
    required this.challengeId,
    required this.onChanged,
    this.expiresAt,
    required this.onCompleted,
    this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final hint = text.bodySmall.copyWith(color: colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the $codeLength-digit code we sent to $destination.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: MyazaSpacing.lg),
        OtpInput(
          key: ValueKey(challengeId),
          length: codeLength,
          style: style,
          enabled: enabled,
          onChanged: onChanged,
          onCompleted: onCompleted,
        ),
        const SizedBox(height: MyazaSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: expiresAt == null
                  ? Text('The code expires in 5 minutes.', style: hint)
                  : ExpiryCountdown(expiresAt: expiresAt!, style: hint),
            ),
            TextButton(
              onPressed: onResend,
              child: Text(
                'Resend code',
                style: hint.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      onResend == null ? colors.textSecondary : colors.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
