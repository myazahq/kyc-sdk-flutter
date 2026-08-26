import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import '../services/api_service.dart';
import 'key_people_await_card.dart';
import 'key_people_await_row.dart';

export 'key_people_pending.dart';

// "Awaiting users" — the KYB success screen's people section, rendered from the
// SERVER's reconciled list. Registry discovery can add people the applicant
// never listed, so the rows come from the session summary once it settles,
// never from what was typed.
//
// ONE list, which is the point. Flutter used to render the applicant's draft
// invites above this with their own copy/share buttons, so the same people
// appeared twice and a reader had to hold both to answer "who still owes me
// something". The link now lives on the row it belongs to. Mirrors the RN
// SDK's KeyPeopleAwaitList and the web SDK's.

const List<(String, String)> _sections = [
  ('beneficial_owner', 'UBOS'),
  ('director', 'DIRECTORS'),
  ('signatory', 'SIGNATORIES'),
  ('shareholder', 'SHAREHOLDERS'),
  ('authorized_representative', 'REPRESENTATIVES'),
];

/// Ownership as the list renders it: a whole number where that is honest.
String? _formatPct(double? pct) {
  if (pct == null || !pct.isFinite) return null;
  if (pct == pct.roundToDouble()) return pct.toStringAsFixed(0);
  return pct.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}

/// Server payload → display rows.
List<AwaitRow> rowsFromServer(List<AwaitingPerson> people) => [
      for (final p in people)
        AwaitRow(
          name: p.name,
          role: p.role,
          pct: _formatPct(p.ownershipPct),
          country: p.country,
          status: p.status,
          inviteUrl: p.inviteUrl,
          isApplicant: p.isApplicant,
          isCorporate: p.isCorporate,
        ),
    ];

class KeyPeopleAwaitList extends StatelessWidget {
  const KeyPeopleAwaitList({super.key, required this.people});

  final List<AwaitingPerson> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final text = context.myazaText;
    final colors = context.myazaColors;
    final rows = rowsFromServer(people);

    // Anything whose role we have no section for still has to appear. Quietly
    // dropping people from a "who still owes a check" list is the worst
    // failure it could have.
    final known = _sections.map((s) => s.$1).toSet();
    final groups = <(String, List<AwaitRow>)>[
      for (final (role, label) in _sections)
        if (rows.any((r) => r.role == role))
          (label, [for (final r in rows) if (r.role == role) r]),
    ];
    final others = [for (final r in rows) if (!known.contains(r.role)) r];
    if (others.isNotEmpty) groups.add(('OTHER PEOPLE', others));

    final outstanding =
        rows.where((r) => r.status == 'pending' || r.status == 'failed').length;

    // Entrance stagger, mirroring the web SDK: cards rise in reading order,
    // ~45ms apart, capped so a long roster is not a slow reveal. Together
    // with the skeleton this list replaces (drawn at the same geometry), the
    // hand-off reads as the ghost roster resolving into the real one.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    var entranceIndex = 0;

    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            outstanding == 0
                ? 'Everyone on this application has completed their identity check.'
                : 'To complete the review, the people below must verify their '
                    'identity with a KYC check. Anyone with an email on file has '
                    'already been sent their link.',
            textAlign: TextAlign.center,
            style: text.bodySmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: MyazaSpacing.md),
          for (final (label, groupRows) in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: MyazaSpacing.xs + 2),
              child: Text(
                label,
                style: text.bodySmall.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            for (final row in groupRows)
              _entrance(KeyPeopleAwaitCard(row: row), entranceIndex++, reduceMotion),
            const SizedBox(height: MyazaSpacing.sm),
          ],
          if (outstanding > 0)
            Padding(
              // Clear air below: this caption is the list's last element and
              // the Done button renders immediately after it.
              padding: const EdgeInsets.only(
                top: MyazaSpacing.xs,
                bottom: MyazaSpacing.lg,
              ),
              child: Text(
                'Links are valid for 14 days.',
                textAlign: TextAlign.center,
                style: text.bodySmall.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rise-and-fade entrance for one card; static under OS reduce-motion.
Widget _entrance(Widget child, int index, bool reduceMotion) {
  if (reduceMotion) return child;
  return child
      .animate(delay: (45 * math.min(index, 8)).ms)
      .fadeIn(duration: 300.ms, curve: Curves.easeOut)
      .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOut);
}
