import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../config/business.dart';
import '../config/business_application.dart' show KeyPersonEntry;
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import 'country_flag.dart';

// ─── "Awaiting users" — key-people section of the KYB success screen ──────────
//
// Every person the review is waiting on, grouped by role, each with a status
// pill; pending people carry a copyable verification link, and the APPLICANT
// (who verified in-flow) appears with a green Submitted pill so the picture is
// complete. Mirrors the web SDK's KeyPeopleInviteLinks 1:1. Links stay valid
// for 14 days; people with an email on file also receive theirs automatically.

class _AwaitRow {
  final String name;
  final ApplicantRole role;
  final String? pct;
  final String? country;
  final bool submitted;
  final String? inviteUrl;
  final bool isApplicant;

  const _AwaitRow({
    required this.name,
    required this.role,
    this.pct,
    this.country,
    required this.submitted,
    this.inviteUrl,
    this.isApplicant = false,
  });
}

const List<(ApplicantRole, String)> _sections = [
  (ApplicantRole.beneficialOwner, 'UBOS'),
  (ApplicantRole.director, 'DIRECTORS'),
  (ApplicantRole.signatory, 'SIGNATORIES'),
  (ApplicantRole.shareholder, 'SHAREHOLDERS'),
  (ApplicantRole.authorizedRepresentative, 'REPRESENTATIVES'),
];

class KeyPeopleInviteLinks extends ConsumerWidget {
  final List<KeyPersonInvite> invites;

  const KeyPeopleInviteLinks({super.key, required this.invites});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (invites.isEmpty) return const SizedBox.shrink();
    final text = context.myazaText;
    final colors = context.myazaColors;
    final s = ref.watch(kYCNotifierProvider);

    final rows = <_AwaitRow>[];

    // The applicant themselves — verified in-flow, nothing more to do.
    final applicantRole = s.applicantRole;
    if (applicantRole != null) {
      final selfIndex = s.applicantKeyPersonIndex;
      final self = selfIndex != null && selfIndex < s.keyPeople.length
          ? s.keyPeople[selfIndex]
          : null;
      final selfName = (self?.name ?? s.applicantName ?? '').trim();
      final selfCountry = self?.country.trim() ?? '';
      rows.add(_AwaitRow(
        name: selfName.isEmpty ? 'You' : selfName,
        role: self != null
            ? ApplicantRole.values.byName(self.role.name)
            : applicantRole,
        pct: (self?.ownershipPct.trim().isNotEmpty ?? false)
            ? self!.ownershipPct.trim()
            : null,
        country: selfCountry.isEmpty ? null : selfCountry.toUpperCase(),
        submitted: true,
        isApplicant: true,
      ));
    }

    // Everyone the server minted a link for — enriched from the entered rows.
    for (final invite in invites) {
      KeyPersonEntry? entered;
      for (final p in s.keyPeople) {
        if (p.name.trim() == invite.name.trim()) {
          entered = p;
          break;
        }
      }
      final country = entered?.country.trim() ?? '';
      rows.add(_AwaitRow(
        name: invite.name,
        role: entered != null
            ? ApplicantRole.values.byName(entered.role.name)
            : ApplicantRole.director,
        pct: (entered?.ownershipPct.trim().isNotEmpty ?? false)
            ? entered!.ownershipPct.trim()
            : null,
        country: country.isEmpty ? null : country.toUpperCase(),
        submitted: false,
        inviteUrl: invite.inviteUrl,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'To complete the review, the people below must verify their '
          'identity with a KYC check. Anyone with an email on file has '
          'already been sent their link.',
          style: text.bodySmall.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.md),
        for (final (role, label) in _sections)
          if (rows.any((r) => r.role == role)) ...[
            Text(
              label,
              style: text.bodySmall.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: MyazaSpacing.xs + 2),
            for (final row in rows.where((r) => r.role == role)) ...[
              _AwaitCard(row: row),
              const SizedBox(height: MyazaSpacing.sm),
            ],
            const SizedBox(height: MyazaSpacing.xs),
          ],
        Center(
          child: Text(
            'Links are valid for 14 days.',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _AwaitCard extends StatefulWidget {
  final _AwaitRow row;

  const _AwaitCard({required this.row});

  @override
  State<_AwaitCard> createState() => _AwaitCardState();
}

class _AwaitCardState extends State<_AwaitCard> {
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
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${row.role.label}'
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
                  color: row.submitted ? colors.successBg : colors.primary100,
                  borderRadius: BorderRadius.circular(MyazaRadius.full),
                ),
                child: Text(
                  row.submitted ? 'SUBMITTED' : 'KYC PENDING',
                  style: text.bodySmall.copyWith(
                    color:
                        row.submitted ? MyazaColors.success : colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (!row.submitted && row.inviteUrl != null) ...[
            const SizedBox(height: MyazaSpacing.sm + 4),
            // Both actions, since it's mobile: Copy for pasting anywhere,
            // Share for the native sheet (WhatsApp/SMS directly).
            Row(
              children: [
                Expanded(
                  child: _ActionPill(
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
                    builder: (pillContext) => _ActionPill(
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
class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Material(
      color: colors.primary100,
      borderRadius: BorderRadius.circular(MyazaRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.sm + 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(width: MyazaSpacing.xs + 2),
              Text(
                label,
                style: text.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
