import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Held while the register is reconciled against what the applicant typed.
///
/// A SKELETON of the roster it becomes, not a spinner line (mirrors the web
/// and RN SDKs' KeyPeoplePending): ghost cards drawn at the real cards'
/// geometry reserve the space so the answer lands in place, and the shape
/// itself says "a list of people is coming" where a spinner only says "busy".
/// A blank here reads as "nobody needs to verify", the opposite of true. The
/// status line is a live region for assistive tech; the shimmer respects the
/// OS reduce-motion setting. Seconds, normally; the controller behind it
/// gives up rather than spinning forever.
class KeyPeoplePending extends StatefulWidget {
  const KeyPeoplePending({super.key});

  @override
  State<KeyPeoplePending> createState() => _KeyPeoplePendingState();
}

class _KeyPeoplePendingState extends State<KeyPeoplePending>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final opacity = Tween<double>(begin: 1.0, end: 0.45)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            label: 'Working out who else needs to verify. We are checking the '
                "official register for the company's directors and owners.",
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: MyazaSpacing.sm),
                      Flexible(
                        child: Text(
                          'Working out who else needs to verify',
                          style: text.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyazaSpacing.xs),
                  // Naming the authority is the reassurance: the pause is the
                  // official register being consulted, not the app hanging.
                  Text(
                    'We are checking the official register for the '
                    "company's directors and owners.",
                    textAlign: TextAlign.center,
                    style: text.bodySmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MyazaSpacing.md),
          // The ghost roster: geometry, not information — hidden from
          // assistive tech, the live region above carries the message.
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GhostBar(opacity: opacity, width: 64, height: 10, color: colors.border),
                ),
                const SizedBox(height: MyazaSpacing.xs + 2),
                _GhostCard(opacity: opacity, colors: colors, withLink: true),
                _GhostCard(opacity: opacity, colors: colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostCard extends StatelessWidget {
  const _GhostCard({required this.opacity, required this.colors, this.withLink = false});

  final Animation<double> opacity;
  final MyazaColorScheme colors;
  final bool withLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MyazaSpacing.sm),
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
                    _GhostBar(opacity: opacity, width: 140, height: 14, color: colors.border),
                    const SizedBox(height: 6),
                    _GhostBar(opacity: opacity, width: 200, height: 10, color: colors.border),
                  ],
                ),
              ),
              const SizedBox(width: MyazaSpacing.sm),
              _GhostBar(opacity: opacity, width: 76, height: 22, color: colors.border, round: true),
            ],
          ),
          if (withLink) ...[
            const SizedBox(height: MyazaSpacing.sm + 4),
            _GhostBar(opacity: opacity, height: 38, color: colors.primary100, round: true),
          ],
        ],
      ),
    );
  }
}

class _GhostBar extends StatelessWidget {
  const _GhostBar({
    required this.opacity,
    required this.height,
    required this.color,
    this.width,
    this.round = false,
  });

  final Animation<double> opacity;
  final double? width;
  final double height;
  final Color color;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(round ? 999 : 4),
        ),
      ),
    );
  }
}
