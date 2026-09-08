import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import '../widgets/myaza_pulse_loader.dart';

// ─── The one loading screen ─────────────────────────────────────────────────
//
// Every wait after the capture renders THIS, with copy from
// config/result_copy.dart: the selfie upload, the submission and (on a flow
// that waits for its verdict) the status poll all show one loader under one
// title. Three screens with three sentences read as three things going wrong;
// one screen reads as the check running. A retry in flight swaps only the
// description, in the warning colour. Mirrors the RN SubmittedWaiting.

class SubmittedWaitingView extends StatelessWidget {
  final String title;
  final String description;
  final bool retrying;

  const SubmittedWaitingView({
    super.key,
    required this.title,
    required this.description,
    this.retrying = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: MyazaSpacing.xl),
        const MyazaPulseLoader(),
        const SizedBox(height: MyazaSpacing.lg),
        Text(title, style: text.heading3, textAlign: TextAlign.center)
            .animate()
            .fadeIn(duration: 400.ms),
        const SizedBox(height: MyazaSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.lg),
          child: Text(
            description,
            style: retrying ? text.bodyMedium.copyWith(color: MyazaColors.warning) : text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: MyazaSpacing.xl),
      ],
    );
  }
}
