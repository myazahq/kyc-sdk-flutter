import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';
import 'liveness_blur_scope.dart';

// ─── Surfaces for content over the camera ────────────────────────────────────
//
// The room behind the camera can be any colour, so words never sit on it
// directly: each carries its own surface. Where the phone can afford it the
// surface is frosted; where it cannot (liveness_blur_scope.dart) it is opaque.

/// One line fills the ends fully round; a wrapped second line keeps soft
/// corners instead of being squeezed into a capsule.
const double _kPillRadius = 24;

Widget _surface(
  BuildContext context, {
  required BorderRadius radius,
  required EdgeInsets padding,
  required double opacity,
  required Widget child,
}) {
  final colors = context.myazaColors;
  final blurs = LivenessBlurScope.of(context);
  final box = Container(
    padding: padding,
    decoration: BoxDecoration(
      color: colors.background.withValues(alpha: blurs ? opacity : 1),
      borderRadius: radius,
      border: Border.all(
        color: colors.border.withValues(alpha: blurs ? 0.7 : 1),
      ),
    ),
    child: child,
  );
  return ClipRRect(
    borderRadius: radius,
    child: blurs
        ? BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: box,
          )
        : box,
  );
}

/// A frosted pill for text over the camera.
class LivenessFrostedPill extends StatelessWidget {
  const LivenessFrostedPill({
    super.key,
    required this.child,
    this.opacity = 0.78,
  });

  final Widget child;

  /// How solid the pill is. Text that has to be read at a glance (the
  /// instruction, a warning) asks for more than a quiet caption does.
  final double opacity;

  @override
  Widget build(BuildContext context) => _surface(
        context,
        radius: BorderRadius.circular(_kPillRadius),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        opacity: opacity,
        child: child,
      );
}

/// A rounded frosted surface for a block of content over the camera.
class LivenessFrostedPanel extends StatelessWidget {
  const LivenessFrostedPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _surface(
        context,
        radius: BorderRadius.circular(MyazaRadius.md),
        padding: const EdgeInsets.all(MyazaSpacing.md),
        opacity: 0.88,
        child: child,
      );
}

/// The line on the bottom edge: what happens to the picture being taken.
///
/// Shown from the moment the camera opens until the photo is taken, then it
/// fades out ([visible] false). One quiet line in the secondary text colour,
/// so it does not compete with the instruction above the window.
class LivenessReassurance extends StatelessWidget {
  const LivenessReassurance({super.key, this.visible = true});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: LivenessFrostedPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MyazaIcon(MyazaIcons.lock, size: 13, color: colors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Your selfie is sent over a secure connection',
                  style: text.bodySmall.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plate the gesture animation sits on over the camera: a solid white
/// disc with a ring and a shadow, so the cartoon reads against any room.
class LivenessGesturePlate extends StatelessWidget {
  const LivenessGesturePlate({
    super.key,
    required this.child,
    this.compact = false,
  });

  final Widget child;

  /// Inside the instruction's pill on a short phone: a thinner ring, and no
  /// shadow, since the pill is already its surface.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 2 : 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: context.myazaColors.primary,
          width: compact ? 1.5 : 2,
        ),
        boxShadow: compact
            ? null
            : const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}
