import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';

// ─── Check badge ──────────────────────────────────────────────────────────────
//
// THE success mark for the whole SDK: the circle shown when a verification is
// submitted, and on any intermediate step that completes successfully.
//
// Shared rather than re-invented per screen. A flow that ends on this badge but
// uses a different mark mid-way makes the two moments look unrelated — the user
// should recognise the same "that worked" signal wherever it appears.
//
// The entrance (scale 0.4 → 1 on easeOutBack, with a shorter fade) is part of
// the identity, so it lives here rather than at each call site.

class CheckBadge extends StatelessWidget {
  /// Diameter. The submission screen uses the 88 default; smaller steps can
  /// scale it down without redrawing anything.
  final double size;

  /// Play the entrance. Off when a parent already animates this in, so the two
  /// don't fight.
  final bool animate;

  const CheckBadge({super.key, this.size = 88, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.successBg,
        border: Border.all(
          color: MyazaColors.success.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Icon(
        Icons.check_rounded,
        // Keeps the glyph's proportion to the circle at any size.
        size: size * 0.5,
        color: MyazaColors.success,
      ),
    );

    if (!animate) return badge;

    return badge
        .animate()
        .scale(
          begin: const Offset(0.4, 0.4),
          end: const Offset(1.0, 1.0),
          duration: 450.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 200.ms);
  }
}
