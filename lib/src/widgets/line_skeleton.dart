import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── A text line that is on its way ─────────────────────────────────────────
//
// Drawn at the line's own height so the card around it does not move when the
// words land, and shaped like the answer (a rounded bar about the width of a
// short address) rather than a spinner: a spinner beside grey text says
// "busy", a bar where the text goes says "the line is coming" (user decision
// 2026-09-07). The pin summary and the review card use it while the reverse
// geocode is out. It pulses the way KeyPeoplePending's ghost roster does, so
// the SDK has one skeleton language, and holds still under the OS
// reduce-motion setting. The words still reach assistive tech through the
// live-region label.
//
// Mirrors the web SDK's components/LineSkeleton and React Native's
// components/LineSkeleton.tsx.

class LineSkeleton extends StatefulWidget {
  /// What a screen reader hears, e.g. "Finding the address…".
  final String label;

  /// The style the real line renders with, so the ghost owns its height.
  final TextStyle style;

  /// How much of the line the bar covers; an address, not a paragraph.
  final double widthFactor;

  const LineSkeleton({
    super.key,
    required this.label,
    required this.style,
    this.widthFactor = 0.62,
  });

  @override
  State<LineSkeleton> createState() => _LineSkeletonState();
}

class _LineSkeletonState extends State<LineSkeleton>
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
    final colors = context.myazaColors;
    final barHeight = ((widget.style.fontSize ?? 14) * 0.7).roundToDouble();
    final opacity = Tween<double>(begin: 1.0, end: 0.45)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // An invisible line in the real style owns the height, so the
            // card does not move when the words replace the bar.
            SizedBox(
              width: double.infinity,
              child: Opacity(
                opacity: 0,
                child: Text(' ', style: widget.style, maxLines: 1),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widget.widthFactor,
                  child: FadeTransition(
                    opacity: opacity,
                    child: Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: colors.primary100,
                        borderRadius: BorderRadius.circular(barHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
