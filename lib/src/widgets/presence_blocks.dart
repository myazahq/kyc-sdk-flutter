import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import 'presence_milestone_track.dart';
import 'presence_milestones.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';

/// The success screen's presence card, drawn as a LIVE PROCESS rather than a
/// notice: the check began the moment they submitted, so the badge pulses and
/// the first milestone is already filled.
///
/// Its copy is a lockstep mirror of the web and RN SDKs' PresenceExpectations,
/// and of the intro gate's milestones — the promise made at the start of the
/// address flow and the card at the end are two frames of one story.
class PresenceExpectations extends StatelessWidget {
  const PresenceExpectations({super.key});

  @override
  Widget build(BuildContext context) {
    // Catalogue texts (a workflow may reword them); defaults in i18n/.
    final t = context.kycText;
    PresenceMilestone milestone(int n, MyazaIconData icon) => PresenceMilestone(
          icon: icon,
          stage: t('address.presence.step$n.stage'),
          title: t('address.presence.step$n.title'),
          caption: t('address.presence.step$n.caption'),
          active: n == 1,
        );
    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.lg),
      child: PresenceCard(
        header: PresenceHeaderBand(
          badge: PresenceBadge(
            leading: const _LiveDot(),
            label: t('address.presence.badge'),
          ),
          title: t('address.presence.title'),
          body: t('address.presence.description'),
          compact: true,
        ),
        track: PresenceMilestoneTrack(
          milestones: [
            milestone(1, MyazaIcons.mapPinCheck),
            milestone(2, MyazaIcons.radar),
            milestone(3, MyazaIcons.bellRing),
          ],
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
