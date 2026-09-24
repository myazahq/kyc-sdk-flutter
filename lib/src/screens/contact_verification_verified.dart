import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/myaza_button.dart';
import '../widgets/icons/icons.dart';

// ─── Contact verification — the already-verified panel ────────────────────────
//
// Split out of contact_verification_parts.dart to keep both files inside the
// 200-line limit. The primary-tinted card matches the web and React Native
// SDKs: this is the one moment in the step that reports success, so it should
// read as a result rather than another line of copy.

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
              MyazaIcon(MyazaIcons.circleCheck, color: colors.primary),
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
