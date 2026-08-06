import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../services/mrz_parser.dart';

// ─── Scanned identity card ────────────────────────────────────────────────────
//
// What the chip actually returned, shown back for confirmation. Each value is
// LABELLED and on its own line: the earlier single "NAME · NUMBER" row gave no
// clue what the second value was, and truncated the document number — the one
// field a user checks character-by-character against the printed page.

/// Confirms what the MRZ scan read, so the wrong document is obvious before the
/// chip read rather than after an opaque BAC failure.
class NfcScannedSummary extends StatelessWidget {
  final MrzScan scan;

  const NfcScannedSummary({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final name = scan.displayName;

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: colors.primary50,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Optically aligns the tick with the first line of text rather than
            // the block's centre, which drifts as the name wraps.
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.circleCheck, size: 18, color: colors.primary),
          ),
          const SizedBox(width: MyazaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty) ...[
                  _label(text, colors, 'Name'),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    // WRAPS rather than truncates. An MRZ name can be long, and
                    // an ellipsis on the one field the user is checking defeats
                    // the confirmation.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: MyazaSpacing.sm),
                ],
                _label(text, colors, 'Document number'),
                const SizedBox(height: 2),
                Text(
                  scan.documentNumber,
                  style: text.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textDark,
                    // Tabular figures + tracking: this is the field a user
                    // checks character-by-character against the printed page,
                    // so even advance widths and airy spacing do real work.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Small caps-ish field label. Named fields beat a middot-joined string: the
  /// old "NAME · B51305135" gave no clue what the second value was.
  Widget _label(MyazaThemeText text, MyazaColorScheme colors, String value) =>
      Text(
        value.toUpperCase(),
        style: text.bodySmall.copyWith(
          color: colors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}
