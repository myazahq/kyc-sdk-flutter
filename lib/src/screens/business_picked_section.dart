import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'business_picked_card.dart';
import 'business_sandbox_toggle.dart';

// ─── The picked-company section ───────────────────────────────────────────────
//
// The card, what Continue is about to do, and the dev-only test-result pin.
// Split from business_details_screen.dart (200-line rule); mirrors the web and
// RN SDKs' BusinessPickedSection.

class BusinessPickedSection extends StatelessWidget {
  final String country;
  final String name;
  final String registrationNumber;
  final bool isSandbox;
  final VoidCallback onChange;

  const BusinessPickedSection({
    super.key,
    required this.country,
    required this.name,
    required this.registrationNumber,
    required this.isSandbox,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BusinessPickedCard(
          country: country,
          name: name,
          registrationNumber: registrationNumber,
          onChange: onChange,
        ),
        const SizedBox(height: MyazaSpacing.lg),
        // Says what the button is about to do: Continue runs a real lookup
        // against the register, which takes a moment and is charged to the
        // organisation. "Continue" alone made a paid outbound call look like
        // moving to the next page.
        Text(
          'Continue checks this business against the official register and '
          'brings back its details.',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
        ),
        if (isSandbox) ...[
          const SizedBox(height: MyazaSpacing.lg),
          const BusinessSandboxToggle(),
        ],
      ],
    );
  }
}
