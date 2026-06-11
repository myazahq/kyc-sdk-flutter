import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';

/// Branded loading indicator: a pulsing outer ring around a tinted circle with a
/// spinner. Shared by the submitting screen and the ID-type loading state so the
/// loader looks consistent across the flow.
class MyazaPulseLoader extends StatelessWidget {
  /// Outer ring diameter. The inner spinner badge scales to 70% of this.
  final double size;

  const MyazaPulseLoader({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final inner = size * 0.7;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing outer ring.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1.05, 1.05),
                duration: 1000.ms,
                curve: Curves.easeInOut,
              )
              .fadeOut(begin: 0.8, duration: 1000.ms),
          // Inner tinted circle with spinner.
          Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.10),
            ),
            child: Padding(
              padding: EdgeInsets.all(inner * 0.28),
              child: CircularProgressIndicator(
                color: colors.primary,
                strokeWidth: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
