import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'country_flag.dart';
import 'key_people_await_pill.dart';
import 'key_people_await_row.dart';

// One person on the KYB success screen's list: who they are, where their check
// stands, and — while it is still open — the link that gets them there.
//
// The link lives ON the row rather than in a second list above it. Two lists of
// the same people, one with links and one with statuses, is what Flutter had,
// and a reader has to hold both to answer "who still owes me something".
// Mirrors the RN SDK's KeyPeopleAwaitCard.

class KeyPeopleAwaitCard extends StatefulWidget {
  final AwaitRow row;

  const KeyPeopleAwaitCard({super.key, required this.row});

  @override
  State<KeyPeopleAwaitCard> createState() => KeyPeopleAwaitCardState();
}

class KeyPeopleAwaitCardState extends State<KeyPeopleAwaitCard> {
  bool _copied = false;

  Future<void> _copy() async {
    final url = widget.row.inviteUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Opens the native share sheet, ANCHORED to the tapped pill. iOS requires
  /// a `sharePositionOrigin` to place the activity popover (mandatory on
  /// iPad, and newer iOS builds silently refuse to present without one) —
  /// share_plus only fills it in for you on some platforms, so an unanchored
  /// `Share.share(url)` was a button that did nothing. If presenting still
  /// fails, fall back to copying the link — the user always walks away with
  /// it either way.
  Future<void> _share(BuildContext anchor) async {
    final url = widget.row.inviteUrl;
    if (url == null) return;
    final box = anchor.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        url,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      await _copy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final row = widget.row;

    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: row.name,
                          style: text.bodyMedium
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (row.isApplicant)
                          TextSpan(
                            text: '  (you)',
                            style: text.bodySmall
                                .copyWith(color: colors.textSecondary),
                          ),
                        if (row.isCorporate)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.background,
                                  border: Border.all(color: colors.border),
                                  borderRadius:
                                      BorderRadius.circular(MyazaRadius.full),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.building2,
                                      size: 12,
                                      color: colors.textDark,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Company',
                                      style: text.bodySmall.copyWith(
                                        color: colors.textDark,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${roleLabel(row.role)}'
                            '${row.pct != null ? ' · ${row.pct}%' : ''}'
                            '${row.country != null ? ' · ' : ''}',
                            style: text.bodySmall
                                .copyWith(color: colors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (row.country != null) ...[
                          MyazaCountryFlag(country: row.country, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              countryLabel(row.country!),
                              style: text.bodySmall
                                  .copyWith(color: colors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MyazaSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyazaSpacing.sm + 4,
                  vertical: MyazaSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: pillBg(row.status, colors),
                  borderRadius: BorderRadius.circular(MyazaRadius.full),
                ),
                child: Text(
                  pillLabel(row.status, row.isCorporate),
                  style: text.bodySmall.copyWith(
                    color: pillFg(row.status, colors),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (row.inviteUrl != null) ...[
            const SizedBox(height: MyazaSpacing.sm + 4),
            // Both actions, since it's mobile: Copy for pasting anywhere,
            // Share for the native sheet (WhatsApp/SMS directly).
            Row(
              children: [
                Expanded(
                  child: KeyPeopleActionPill(
                    icon: _copied ? LucideIcons.check : LucideIcons.copy,
                    label: _copied ? 'Copied' : 'Copy link',
                    onTap: _copy,
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                Expanded(
                  // Builder so the share sheet anchors to THIS pill's render
                  // box (not the whole card).
                  child: Builder(
                    builder: (pillContext) => KeyPeopleActionPill(
                      icon: LucideIcons.share2,
                      label: 'Share',
                      onTap: () => _share(pillContext),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One tinted pill action (Copy / Share) on a pending person's card.
