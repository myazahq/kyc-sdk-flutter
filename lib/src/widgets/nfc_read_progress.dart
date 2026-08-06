import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../services/nfc_reader.dart';

// ─── NFC read progress ────────────────────────────────────────────────────────
//
// iOS puts a system sheet over the screen for the whole chip read and narrates
// it — "Keep holding — reading security data…", "Reading photo…". Android has
// NO system NFC UI whatsoever, so the same read used to be a bare spinner: the
// user couldn't tell whether the chip had even been detected, let alone that
// three data groups were being pulled off it, and the natural response to that
// silence is to lift the document — which aborts the read.
//
// This draws the narration the platform doesn't. Same wording as the iOS sheet,
// so the two platforms describe the read identically.

class NfcReadProgress extends StatelessWidget {
  final NfcReadStage stage;

  const NfcReadProgress({super.key, required this.stage});

  /// The steps worth showing. `waiting` is not one of them — it is the state
  /// BEFORE any step starts, and it gets its own prominent line above.
  static const _steps = <NfcReadStage>[
    NfcReadStage.authenticating,
    NfcReadStage.readingData,
    NfcReadStage.readingSecurity,
    NfcReadStage.readingPhoto,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final waiting = stage == NfcReadStage.waiting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Waiting is the state users misread as "nothing is happening", so it
        // says what the phone is doing rather than leaving a silent spinner.
        if (waiting)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                NfcReadStage.waiting.label,
                style: text.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        else
          for (final step in _steps) _StepRow(step: step, current: stage),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final NfcReadStage step;
  final NfcReadStage current;

  const _StepRow({required this.step, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    // `done` completes every step: the photo group is skipped when the security
    // object didn't come back, and a step left spinning after a successful read
    // would read as a failure.
    final complete =
        current == NfcReadStage.done || current.index > step.index;
    final active = current == step;

    final Widget leading;
    if (complete) {
      leading = const Icon(LucideIcons.circleCheck,
          size: 16, color: MyazaColors.success);
    } else if (active) {
      leading = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
      );
    } else {
      leading = Icon(LucideIcons.circle, size: 16, color: colors.gray300);
    }

    final color = complete
        ? colors.textSecondary
        : active
            ? colors.primary
            : colors.gray400;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 16, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: text.bodySmall.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
