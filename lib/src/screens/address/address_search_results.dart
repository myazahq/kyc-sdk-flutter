import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/theme.dart';

/// The results container: a bordered list of rows, or the empty line.
///
/// A FAILED search renders the same empty state as a search that genuinely
/// matched nothing. The distinction would not help the applicant here: either
/// way the answer is to use their location or place the pin by hand, and both
/// escapes are already on the screen.
class AddressSearchResults extends StatelessWidget {
  final List<Widget> rows;

  /// Shown when the search came back with nothing. Differs per backend: the
  /// basic search has no autocomplete to fall back on, so it points straight
  /// at the map.
  final String emptyMessage;

  const AddressSearchResults({
    super.key,
    required this.rows,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(emptyMessage,
                  style: text.bodyMedium.copyWith(color: colors.textSecondary)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
    );
  }
}

/// One candidate. Two lines when the backend distinguishes a name from its
/// context (Places), one otherwise.
class AddressSearchResultRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool last;
  final bool disabled;
  final VoidCallback onTap;

  const AddressSearchResultRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.last,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final sub = (subtitle ?? '').trim();
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              last ? null : Border(bottom: BorderSide(color: colors.border)),
        ),
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.mapPin,
                      size: 16, color: colors.primary),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: text.bodyMedium.copyWith(
                              color: colors.textDark,
                              fontWeight: FontWeight.w500,
                              height: 1.35)),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(sub,
                            style: text.bodySmall
                                .copyWith(color: colors.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
