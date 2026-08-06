import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── Pulse ring ───────────────────────────────────────────────────────────────
//
// Exact port of the web SDK's `.animate-pulse-ring` (globals.css):
//
//   @keyframes pulse-ring {
//     0%   { transform: scale(0.9); opacity: 0.7 }
//     50%  { transform: scale(1);   opacity: 0.3 }
//     100% { transform: scale(0.9); opacity: 0.7 }
//   }
//   animation: pulse-ring 2s ease-in-out infinite;
//
// A hollow ring sitting behind a hero glyph. This is the ONE looping element on
// the primer — a second competing animation reads as noise — and it earns the
// exception to "continuous motion is for loading only" by signalling that the
// camera is about to open, not that work is in progress.

class PulseRing extends StatefulWidget {
  /// Ring diameter at full scale. Web: h-20 w-20 → 80.
  final double size;

  const PulseRing({super.key, this.size = 80});

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2), // 2s
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the setting directly — never gate the start on it having CHANGED,
    // or the animation never begins for the majority who have motion enabled.
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    // globals.css disables the animation under prefers-reduced-motion, leaving
    // the ring at its resting size — mirror that rather than hiding it.
    if (_reduced) {
      return _ring(colors, scale: 0.9, opacity: 0.7);
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // 0 → 0.5 → 1 maps to scale 0.9 → 1.0 → 0.9, opacity 0.7 → 0.3 → 0.7,
        // eased at both ends like CSS ease-in-out.
        final half = _c.value < 0.5 ? _c.value * 2 : (1 - _c.value) * 2;
        final t = Curves.easeInOut.transform(half.clamp(0.0, 1.0));
        return _ring(
          colors,
          scale: 0.9 + 0.1 * t,
          opacity: 0.7 - 0.4 * t,
        );
      },
    );
  }

  Widget _ring(
    MyazaColorScheme colors, {
    required double scale,
    required double opacity,
  }) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // border-2 border-primary/30
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}
