import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../liveness/liveness_types.dart';

// ─── Liveness avatar ──────────────────────────────────────────────────────────
//
// Displays an animated GIF demonstrating the required gesture.
// Slides in from below when the challenge changes (AnimatedSwitcher).
// Hidden outside of active challenge phases.

class LivenessAvatar extends StatelessWidget {
  /// The challenge currently being attempted, or null outside challenge phases.
  final LivenessChallenge? activeChallenge;

  /// Current liveness phase — drives whether the avatar is visible.
  final LivenessPhase phase;

  const LivenessAvatar({
    super.key,
    required this.activeChallenge,
    required this.phase,
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
        challenge: challenge,
      ),
    );
  }
}

// ─── Avatar content ───────────────────────────────────────────────────────────

class _AvatarContent extends StatelessWidget {
  final LivenessChallenge challenge;

  const _AvatarContent({super.key, required this.challenge});

  String get _gifAsset => switch (challenge) {
        LivenessChallenge.nod   => 'assets/liveness/Nod.gif',
        LivenessChallenge.turn  => 'assets/liveness/Turn.gif',
        LivenessChallenge.blink => 'assets/liveness/Blink.gif',
        LivenessChallenge.smile => 'assets/liveness/Smile.gif',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.myazaColors.primary100,
          ),
          child: ClipOval(
            child: Image.asset(
              _gifAsset,
              // Required: this code lives inside the myaza_kyc_sdk_flutter package
              // which is a dependency — Flutter resolves assets under
              // packages/myaza_kyc_sdk_flutter/ only when the package name is supplied.
              package: 'myaza_kyc_sdk_flutter',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.face_outlined,
                size: 40,
                color: context.myazaColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

