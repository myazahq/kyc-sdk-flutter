import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'presence_milestones.dart';
import 'icons/icons.dart';

/// The milestone track: a vertical rail, each node wearing its stage label.
///
/// Deliberately vertical at every width. The flow renders in a bottom sheet
/// whose body is a single column, so a three-up row would only ever apply on a
/// tablet, and one layout is one thing to keep true.
class PresenceMilestoneTrack extends StatelessWidget {
  final List<PresenceMilestone> milestones;

  /// Number each node. The sequence is the point on the intro screen; on the
  /// success card the check is already running, so a number would only count
  /// something the applicant has no part in.
  final bool numbered;

  /// Node diameter: 40 on the primer (web h-10, RN NODE), 32 on the success
  /// card (web h-8).
  final double medallion;

  const PresenceMilestoneTrack({
    super.key,
    required this.milestones,
    this.numbered = false,
    this.medallion = 40,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < milestones.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      PresenceMedallion(
                        milestone: milestones[i],
                        size: medallion,
                        number: numbered ? i + 1 : null,
                      ),
                      if (i < milestones.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: colors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            i < milestones.length - 1 ? MyazaSpacing.md : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            milestones[i].stage.toUpperCase(),
                            style: text.bodySmall.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: milestones[i].active
                                  ? colors.primary
                                  : colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(milestones[i].title,
                              style: text.label.copyWith(
                                  fontWeight: FontWeight.w600, height: 1.25)),
                          const SizedBox(height: 3),
                          Text(milestones[i].caption,
                              style: text.bodySmall.copyWith(
                                  color: colors.textSecondary, height: 1.35)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A node's medallion, with its step number when the track is numbered.
class PresenceMedallion extends StatelessWidget {
  final PresenceMilestone milestone;
  final double size;
  final int? number;

  const PresenceMedallion({
    super.key,
    required this.milestone,
    required this.size,
    this.number,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final active = milestone.active;
    // The active node's halo: web's `shadow-[0_0_0_5px] shadow-primary/15`
    // (4px on the smaller success-card node).
    final halo = size >= 40 ? 5.0 : 4.0;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 6,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: active
                    ? colors.primary
                    : colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: active
                    ? null
                    : Border.all(color: colors.primary.withValues(alpha: 0.2)),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.15),
                          spreadRadius: halo,
                        ),
                      ]
                    : null,
              ),
              child: MyazaIcon(milestone.icon,
                  size: size * 0.45,
                  color: active ? colors.onPrimary : colors.primary),
            ),
          ),
          if (number != null)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.background,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: active ? colors.primary : colors.border),
                ),
                child: Text('$number',
                    style: text.bodySmall.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: active ? colors.primary : colors.textSecondary,
                    )),
              ),
            ),
        ],
      ),
    );
  }
}
