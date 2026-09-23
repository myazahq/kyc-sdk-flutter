import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── The pieces of a supporting-document card ────────────────────────────────
//
// Split out of the card itself only for the file-length rule; they are that
// card's own furniture and nothing else builds them.

/// A count while the document is outstanding, and a state anybody can read
/// once it is not. One document needs no number, so it wears a document glyph.
class DocumentMarker extends StatelessWidget {
  const DocumentMarker({
    super.key,
    required this.done,
    required this.position,
    required this.total,
  });

  final bool done;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.primary : colors.primary100,
        shape: BoxShape.circle,
      ),
      child: done
          ? Icon(LucideIcons.check, size: 16, color: colors.onPrimary)
          : total > 1
              ? Text(
                  '$position',
                  style: text.bodySmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(LucideIcons.fileText, size: 14, color: colors.primary),
    );
  }
}

/// Required or optional, in a word as well as a colour.
class DocumentStatePill extends StatelessWidget {
  const DocumentStatePill({super.key, required this.required});

  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: required ? colors.errorBg : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Text(
        required ? 'Required' : 'Optional',
        style: text.bodySmall.copyWith(
          color: required ? MyazaColors.error : colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// What the server will take off this document, named as the author named it.
class DocumentReads extends StatelessWidget {
  const DocumentReads({super.key, required this.reads});

  final List<String> reads;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyazaSpacing.sm + 4),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT WE READ FROM IT',
            style: text.bodySmall.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: MyazaSpacing.sm),
          Wrap(
            spacing: MyazaSpacing.xs + 2,
            runSpacing: MyazaSpacing.xs + 2,
            children: [
              for (final read in reads)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MyazaSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(MyazaRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 12, color: colors.primary),
                      const SizedBox(width: 4),
                      Text(read, style: text.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
