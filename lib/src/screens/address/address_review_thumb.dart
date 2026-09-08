import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../config/theme.dart';

// ─── The entrance thumbnails on the review card ──────────────────────────────
//
// Web's exact geometry, so the three review cards are the same card:
//   hero h-28 (112) rounded-2xl shadow-xl at -bottom-10 right-4
//   second h-20 (80) rounded-xl shadow-lg at right-36 (144)
// Split from address_review_card.dart (200-line rule).

const double kReviewHeroSize = 112;
const double kReviewSecondSize = 80;
const double kReviewOverhang = 40;

/// The entrance, hanging over the map's edge with a background-coloured
/// border so it reads as clipped to the card rather than part of the map.
class ReviewEntranceThumb extends StatelessWidget {
  /// A captured photo on disk, or the framed Street View fetched as bytes.
  final String? path;
  final Uint8List? bytes;
  final double size;

  const ReviewEntranceThumb({
    super.key,
    this.path,
    this.bytes,
    this.size = kReviewHeroSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // The hero wears the card's own radius (16), the smaller one a step down
    // (12): web's rounded-2xl beside rounded-xl.
    final radius = size == kReviewHeroSize ? MyazaRadius.md : MyazaRadius.sm;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.background, width: 4),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 4),
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover)
            : Image.file(File(path!), fit: BoxFit.cover),
      ),
    );
  }
}
