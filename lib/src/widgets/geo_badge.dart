import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── "Your location" badge ───────────────────────────────────────────────────
//
// The pill beside a pinned geo row: primary tint, primary text. It marks a
// GUESS made on the visitor's behalf, never a verdict, and the row it sits on
// is one tap away rather than buried in the alphabet. Shared by the
// country-select picker and the dial-code sheet so the tag reads identically
// wherever the guess is offered. Mirrors the RN SDK's GeoBadge.

class GeoBadge extends StatelessWidget {
  final String label;
  const GeoBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary50,
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: text.bodySmall.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
