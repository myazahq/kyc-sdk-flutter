import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── The presence story, as one shape ────────────────────────────────────────
//
// The promise made on the address intro screen and the "check active" card on
// the success screen are two frames of ONE story, so they are drawn from the
// same parts: a flat tinted header band, then three milestones on a track.
// Keeping them one widget is what stops the two ends of the flow drifting into
// different designs. Mirrors the web SDK's AddressIntroGate and
// presence-expectations; keep the copy in lockstep.
//
// The track itself lives in presence_milestone_track.dart (200-line rule).

/// One node on the track. [active] nodes are filled; the rest are TINTED, not
/// greyed out: they are the plan, not disabled controls.
class PresenceMilestone {
  final IconData icon;
  final String stage;
  final String title;
  final String caption;
  final bool active;

  const PresenceMilestone({
    required this.icon,
    required this.stage,
    required this.title,
    required this.caption,
    this.active = false,
  });
}

/// The band above the track: an eyebrow pill, a title, and one line of body.
class PresenceHeaderBand extends StatelessWidget {
  final Widget badge;
  final String title;
  final String body;

  /// The success card's title is a step smaller than the primer's (web:
  /// `text-sm` beside `text-base`): the check is already running there, so
  /// the band reads as a status line rather than a screen heading.
  final bool compact;

  const PresenceHeaderBand({
    super.key,
    required this.badge,
    required this.title,
    required this.body,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      width: double.infinity,
      color: colors.primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.fromLTRB(
          MyazaSpacing.md, MyazaSpacing.md, MyazaSpacing.md, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const SizedBox(height: MyazaSpacing.xs),
          Text(title,
              style: compact
                  ? text.bodyMedium.copyWith(
                      color: colors.textDark, fontWeight: FontWeight.w600)
                  : text.body.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
          const SizedBox(height: 2),
          Text(body,
              style: text.bodySmall
                  .copyWith(color: colors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}

/// The eyebrow pill: an icon (or a live dot) plus a short uppercase label.
class PresenceBadge extends StatelessWidget {
  final Widget leading;
  final String label;

  const PresenceBadge({super.key, required this.leading, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: MyazaSpacing.sm),
          // Web's `text-[11px] font-semibold uppercase tracking-wider`, the
          // same numbers RN draws, so the three badges are one badge. The
          // label may SHRINK: the pill sits in rows that clear a thumbnail,
          // and a label that cannot give way draws the overflow stripe on a
          // narrow phone or a large text scale (every host is a bounded
          // Column, which Flexible needs).
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole card: header band over the track, inside one tinted border.
class PresenceCard extends StatelessWidget {
  final Widget header;
  final Widget track;

  const PresenceCard({super.key, required this.header, required this.track});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
        // Web's rounded-2xl (16), the radius RN and the review card wear.
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, track],
      ),
    );
  }
}
