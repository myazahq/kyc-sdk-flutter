import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../liveness/liveness_types.dart';

// ─── Liveness avatar ──────────────────────────────────────────────────────────
//
// Displays an animated demonstration of the required gesture.
// Slides in from below when the challenge changes (AnimatedSwitcher).
// Hidden outside of active challenge phases.
//
// The animation is FETCHED, not bundled (see config/liveness_avatar_url.dart):
// four GIFs in this package were 5.7 MB in every integrator's app for a badge
// the liveness step shows for seconds. The screen resolves the URL and
// precaches all four when liveness opens, so by the time this builds the file
// is normally already in the image cache; when it is not, `errorBuilder`
// renders the gesture icon exactly as it always did for a failed decode.

class LivenessAvatar extends StatelessWidget {
  /// The challenge currently being attempted, or null outside challenge phases.
  final LivenessChallenge? activeChallenge;

  /// Current liveness phase — drives whether the avatar is visible.
  final LivenessPhase phase;

  /// The badge diameter. 80 on a tall phone; the screen hands a smaller size
  /// down on a short one (liveness/liveness_layout.dart) so the gesture stays
  /// on screen beside the circle.
  final double size;

  /// The fallback icon when the animation cannot load.
  final double iconSize;

  /// The served animation for [activeChallenge], resolved by the screen (which
  /// holds the config). Null when the key is malformed, which renders the icon.
  final String? avatarUrl;

  const LivenessAvatar({
    super.key,
    required this.activeChallenge,
    required this.phase,
    this.size = 80,
    this.iconSize = 40,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final challenge = activeChallenge;
    final isVisible = phase == LivenessPhase.challenge ||
        phase == LivenessPhase.challengePassed ||
        phase == LivenessPhase.positioning;

    if (!isVisible || challenge == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: _AvatarContent(
        key: ValueKey(challenge),
        avatarUrl: avatarUrl,
        size: size,
        iconSize: iconSize,
      ),
    );
  }
}

// ─── Avatar content ───────────────────────────────────────────────────────────

class _AvatarContent extends StatelessWidget {
  final String? avatarUrl;
  final double size;
  final double iconSize;

  const _AvatarContent({
    super.key,
    required this.avatarUrl,
    required this.size,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.myazaColors.primary100,
          ),
          child: ClipOval(
            child: avatarUrl == null
                ? _fallbackIcon(context)
                : Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    // A frame still in flight shows the icon rather than a gap,
                    // so the badge never renders empty on a cold cache.
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : _fallbackIcon(context),
                    errorBuilder: (_, __, ___) => _fallbackIcon(context),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackIcon(BuildContext context) => Center(
        child: Icon(
          LucideIcons.scanFace,
          size: iconSize,
          color: context.myazaColors.primary,
        ),
      );
}

