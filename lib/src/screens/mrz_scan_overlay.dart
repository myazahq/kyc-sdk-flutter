import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── MRZ scan overlay ─────────────────────────────────────────────────────────
//
// Camera preview with a guide band over the Machine Readable Zone — the two
// filler-padded lines across the bottom of a passport's photo page. Aiming the
// user at that band (rather than the whole document) is what makes the read
// land quickly: the recognizer only has to resolve the strip that matters.

class MrzScanOverlay extends StatelessWidget {
  final CameraController controller;

  const MrzScanOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          child: AspectRatio(
            // A passport opened flat is close to 3:2; framing the preview to it
            // keeps the whole photo page in shot.
            aspectRatio: 3 / 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.previewSize?.height ?? 720,
                    height: controller.value.previewSize?.width ?? 1280,
                    child: CameraPreview(controller),
                  ),
                ),
                // Dim everything except the MRZ band so the guide reads clearly.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.34,
                    child: Container(
                      margin: const EdgeInsets.all(MyazaSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.primary, width: 2),
                        borderRadius: BorderRadius.circular(MyazaRadius.xs),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: MyazaSpacing.md),
        Text(
          'Line up the two rows of letters and « symbols at the bottom of the '
          'photo page.',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
