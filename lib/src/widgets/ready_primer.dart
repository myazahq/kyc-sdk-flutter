import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import 'myaza_button.dart';
import 'pulse_ring.dart';
import 'ready_primer_content.dart';

/// "Here's what happens next" screen, shown once before a capture step opens
/// the camera.
///
/// It exists because the camera used to appear unannounced: a user who doesn't
/// know their ID or their face is about to be photographed fumbles the first
/// attempt, and a retake costs more than a sentence of warning.
///
/// A port of the web SDK's ReadyPrimer — same minimal single-column shape (one
/// hero, at most three expectations, one primary action) and the same copy, so
/// the flow reads identically whichever SDK the org embeds.
///
/// It sits BEFORE [CameraPermissionPrimingView]: first what we're about to do,
/// then the OS prompt. Two asks in a row, each with a reason, never a surprise.
class ReadyPrimer extends StatelessWidget {
  const ReadyPrimer({
    super.key,
    required this.content,
    required this.onReady,
    this.buttonLabel = "I'm ready",
  });

  final ReadyContent content;
  final VoidCallback onReady;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    // TOP-ALIGNED, like the web. The sheet body guarantees the child at least
    // the viewport height, so a Center here parked the whole primer in the
    // middle of the sheet and left a dead band under the step indicator.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.md),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero — matches the permission primer's icon treatment so the two
            // screens read as one sequence rather than two different designs.
            Container(
              // px-6 py-9
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.05),
                border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(MyazaRadius.lg),
              ),
              child: Column(
                children: [
                  // Ring behind the glyph — the web's `animate-pulse-ring`.
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const PulseRing(),
                        Container(
                          width: 64, // h-16 w-16
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(content.icon,
                              size: 28, color: colors.primary), // h-7 w-7
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MyazaSpacing.md), // gap-4
                  Text(content.title,
                      style: text.heading3, textAlign: TextAlign.center),
                  const SizedBox(height: 6), // space-y-1.5
                  Text(
                    content.body,
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20), // space-y-5

            // Expectations — same row idiom as the consent screen's
            // "during this process we will" list.
            for (final item in content.checklist) ...[
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(MyazaRadius.xs),
                    ),
                    child: Icon(item.icon, size: 18, color: colors.primary),
                  ),
                  const SizedBox(width: 12), // gap-3
                  Expanded(
                    child: Text(item.label, style: text.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12), // space-y-3
            ],

            const SizedBox(height: 8),
            // One primary action. MyazaButton already clears the 44pt minimum.
            MyazaButton(label: buttonLabel, onPressed: onReady),
          ],
        ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
