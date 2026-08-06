import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../services/nfc_reader.dart';
import 'nfc_read_progress.dart';

// ─── NFC read sheet (Android) ─────────────────────────────────────────────────
//
// iOS puts its own system sheet over the app for the whole chip read and
// narrates it. Android has no system NFC UI at all, so this is the equivalent:
// a modal sheet that owns the screen while the chip is being read, says what is
// happening at each step, and — most importantly — makes it obvious that
// something IS happening. A silent screen during a chip read is what makes
// people lift the document, which aborts it.
//
// Deliberately dismissible. The read keeps running if it is swiped away (the
// step list stays on the page behind it), because trapping someone behind a
// sheet they cannot close is worse than letting them look at the screen under
// it.

/// Shows the reading sheet and returns a handle for closing it. Android-only —
/// iOS already has the system sheet, and two would fight.
Future<void> showNfcReadSheet(
  BuildContext context, {
  required ValueListenable<NfcReadStage> stage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NfcReadSheet(stage: stage),
  );
}

class _NfcReadSheet extends StatelessWidget {
  final ValueListenable<NfcReadStage> stage;

  const _NfcReadSheet({required this.stage});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return ValueListenableBuilder<NfcReadStage>(
      valueListenable: stage,
      builder: (context, current, _) {
        final waiting = current == NfcReadStage.waiting;
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MyazaRadius.lg),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
              MyazaSpacing.lg, MyazaSpacing.sm, MyazaSpacing.lg, MyazaSpacing.lg),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.gray300,
                      borderRadius: BorderRadius.circular(MyazaRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: MyazaSpacing.lg),

                _PulsingChipIcon(waiting: waiting),
                const SizedBox(height: MyazaSpacing.md),

                Text(
                  // Waiting is an instruction; everything after it is a report.
                  waiting ? 'Hold your document to the phone' : 'Reading the chip',
                  style: text.heading3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: MyazaSpacing.xs),
                Text(
                  current.detail,
                  style: text.bodySmall.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: MyazaSpacing.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(MyazaRadius.full),
                  child: LinearProgressIndicator(
                    value: waiting ? null : current.progress,
                    minHeight: 6,
                    backgroundColor: colors.gray300,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                ),
                const SizedBox(height: MyazaSpacing.lg),

                NfcReadProgress(stage: current),
                const SizedBox(height: MyazaSpacing.md),

                Text(
                  'Keep the document still until every step is ticked.',
                  style: text.bodySmall.copyWith(color: colors.gray400),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The chip icon, pulsing while the phone is still hunting for the tag and
/// steady once it has one — the difference between "keep moving it" and "hold
/// exactly there", which is the only thing the user can act on.
class _PulsingChipIcon extends StatelessWidget {
  final bool waiting;

  const _PulsingChipIcon({required this.waiting});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final icon = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary50,
      ),
      child: Icon(LucideIcons.nfc, size: 30, color: colors.primary),
    );

    if (!waiting) return Center(child: icon);
    return Center(
      child: icon
          .animate(onPlay: (c) => c.repeat())
          .scale(
            begin: const Offset(0.94, 0.94),
            end: const Offset(1.06, 1.06),
            duration: 900.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.06, 1.06),
            end: const Offset(0.94, 0.94),
            duration: 900.ms,
            curve: Curves.easeInOut,
          ),
    );
  }
}
