import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import 'presence_milestone_track.dart';
import 'presence_milestones.dart';
import 'icons/icons.dart';

/// The success screen's presence card, drawn as a LIVE PROCESS rather than a
/// notice: the check began the moment they submitted, so the badge pulses and
/// the first milestone is already filled.
///
/// Its copy is a lockstep mirror of the web and RN SDKs' PresenceExpectations,
/// and of the intro gate's milestones — the promise made at the start of the
/// address flow and the card at the end are two frames of one story.
class PresenceExpectations extends StatelessWidget {
  const PresenceExpectations({super.key});

  static const _milestones = [
    PresenceMilestone(
      icon: MyazaIcons.mapPinCheck,
      stage: 'Today',
      title: 'Check started',
      caption: 'Your pin is saved. Keep location on.',
      active: true,
    ),
    PresenceMilestone(
      icon: MyazaIcons.radar,
      stage: 'Next few days',
      title: 'Quiet check-ins',
      caption: 'Your phone confirms it is at your address now and then.',
    ),
    PresenceMilestone(
      icon: MyazaIcons.bellRing,
      stage: 'Then',
      title: 'Confirmed',
      caption: 'You get a notification. That is it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: MyazaSpacing.lg),
      child: PresenceCard(
        header: PresenceHeaderBand(
          badge: PresenceBadge(
            leading: _LiveDot(),
            label: 'Address check active',
          ),
          title: 'Your address confirms itself from here',
          body: 'Nothing else for you to do. Carry on as normal.',
          compact: true,
        ),
        track: PresenceMilestoneTrack(
          milestones: _milestones,
          medallion: 32,
        ),
      ),
    );
  }
}

/// The pulsing dot that says the check is running right now, not scheduled.
class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return SizedBox(
      width: 8,
      height: 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(begin: 1, end: 2.2, duration: 1200.ms)
              .fadeOut(duration: 1200.ms),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: colors.primary, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
