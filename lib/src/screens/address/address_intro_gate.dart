import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../config/theme.dart';
import '../../widgets/myaza_button.dart';
import '../../widgets/presence_milestone_track.dart';
import '../../widgets/presence_milestones.dart';
import 'address_intro_disclosures.dart';
import '../../widgets/icons/icons.dart';

// ─── The presence primer ─────────────────────────────────────────────────────
//
// Shown ONCE, on the address flow's first step, when the workflow verifies
// presence. It replaces that step's body until acknowledged — but the step's
// mount work still runs behind it, so the GPS is warm by the time "Got it" is
// tapped and the pin lands with no hesitation.
//
// Drawn in the SUCCESS CARD's language (the eyebrow badge, the milestone
// track, the header band) so the promise made here and the "address check
// active" card at the end read as two frames of one story. Mirrors the web and
// RN SDKs' AddressIntroGate — keep the copy in lockstep.

// The second milestone's caption depends on which tier the org runs. With
// background geofencing on, the "allow all the time" prompt is coming, and
// OkHi's integration guidance is to say so ONCE, up front, beside the
// education, not to surprise the person with it after capture.
const _kCheckInForeground =
    'Keep location on; your phone confirms it over the coming days.';
const _kCheckInBackground =
    'Allow location all the time when asked. Your phone then confirms it on '
    'its own, even with the app closed.';

class AddressIntroGate extends StatelessWidget {
  final VoidCallback onAcknowledge;

  /// The workflow opts into OS geofencing: the copy names the always prompt.
  final bool background;

  const AddressIntroGate({
    super.key,
    required this.onAcknowledge,
    this.background = false,
  });

  List<PresenceMilestone> get _milestones => [
        const PresenceMilestone(
          icon: MyazaIcons.mapPinHouse,
          stage: 'Your part',
          title: 'Pin your address',
          caption: 'Put the pin right on your building. Takes a minute.',
          active: true,
        ),
        PresenceMilestone(
          icon: MyazaIcons.radar,
          stage: 'After that',
          title: 'Quiet check-ins',
          caption: background ? _kCheckInBackground : _kCheckInForeground,
        ),
        const PresenceMilestone(
          icon: MyazaIcons.bellRing,
          stage: 'Then',
          title: 'Confirmed',
          caption: "You’ll be notified. That is it.",
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PresenceCard(
            header: PresenceHeaderBand(
              badge: PresenceBadge(
                leading: MyazaIcon(MyazaIcons.mapPinCheck,
                    size: 12, color: colors.primary),
                label: 'Address verification',
              ),
              title: "Let’s confirm your address",
              body: 'This address will be verified over the coming days. Your '
                  'part takes a minute; the rest happens on its own.',
            ),
            track: PresenceMilestoneTrack(
              milestones: _milestones,
              numbered: true,
            ),
          ),
          const SizedBox(height: MyazaSpacing.md),
          AddressIntroDisclosures(background: background),
          const SizedBox(height: MyazaSpacing.md),
          MyazaButton(
            label: "Got it, let’s go",
            onPressed: onAcknowledge,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
