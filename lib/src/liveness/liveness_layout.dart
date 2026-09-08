import 'dart:math' as math;
import 'dart:ui' show Size;

import '../config/theme.dart';

// ─── How big the selfie circle and the gesture avatar may be ────────────────
//
// The circle was a fixed [MyazaSizing.cameraCircleSize], which is right on a
// tall phone. On a Samsung S24 (360×780 dp, 176 dp shorter than an iPhone 16
// Pro Max) it owned most of the sheet and the avatar demonstrating the gesture
// sat below the fold — the one thing the step exists to show. So the HEIGHT
// bounds it too: whatever the chrome, the instruction, the step dots, the
// avatar and the footer leave over is what the circle may take, and when it
// is the height that bound the circle, the avatar shrinks with it.
//
// Mirrored in the React Native SDK's lib/livenessLayout.ts; the real phones in
// liveness_layout_test.dart are the shared vectors. Change a number in one and
// change both.

/// The cap is the size this SDK has always drawn; the tall phones keep it.
const double kLivenessCircleMax = MyazaSizing.cameraCircleSize;

/// A face is still usable at 200; below that the ring and the oval guide start
/// to crowd it, so a very short screen scrolls a little instead.
const double kLivenessCircleMin = 200;

/// Everything on the sheet that is NOT the circle: banner + brand row + title
/// + step bar (~250), the instruction line, the dots, the large avatar, the
/// gaps, the step padding and the footer. The same budget as React Native —
/// the two sheets carry the same chrome.
const double kLivenessCircleHeightBudget = 540;

/// The circle keeps the step's own side padding on both sides.
const double kLivenessCircleSideGutter = MyazaSpacing.md * 4;

class LivenessLayout {
  /// Diameter of the camera circle, dp.
  final double circle;

  /// Diameter of the gesture avatar badge, dp.
  final double avatar;

  /// The fallback icon inside the avatar when the GIF cannot load.
  final double avatarIcon;

  const LivenessLayout({
    required this.circle,
    required this.avatar,
    required this.avatarIcon,
  });
}

LivenessLayout livenessLayout(Size window) {
  final byWidth = window.width - kLivenessCircleSideGutter;
  final byHeight = window.height - kLivenessCircleHeightBudget;
  final circle = math.min(math.min(byWidth, byHeight), kLivenessCircleMax)
      .clamp(kLivenessCircleMin, kLivenessCircleMax)
      .toDouble();
  // Only a SHORT screen shrinks the avatar: a narrow one that is tall enough
  // has the room for it whatever the width did to the circle.
  final large = byHeight >= kLivenessCircleMax;
  return LivenessLayout(
    circle: circle,
    avatar: large ? 80 : 64,
    avatarIcon: large ? 40 : 30,
  );
}
