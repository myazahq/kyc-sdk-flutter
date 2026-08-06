import 'dart:ui' show Rect, Offset, Size;

import 'id_types.dart';

// ─── Document guide geometry ──────────────────────────────────────────────────
//
// THE single definition of where the capture guide sits. It is consumed by the
// on-screen overlay AND by the crop that runs after the shutter, so if the two
// ever disagree the user frames against one rectangle and receives another —
// which is exactly what happened when the scan overlay computed its own rect.
//
// Any change here moves the guide and the crop together, on purpose.

/// Share of the viewfinder width the guide spans.
const double kDocumentGuideWidthFraction = 0.88;

/// Upward nudge so the shutter button clears the guide's bottom edge.
const double kDocumentGuideTopShift = 20.0;

/// Ceiling on the guide's height, as a share of the viewfinder.
///
/// Width alone is not enough. Deriving height from width means a SQUARER
/// document (a passport page at 1.42 vs a card at 1.586) grows taller, and on a
/// wide phone it overflowed: 253pt of a 300pt viewfinder, top edge 3.6pt from
/// the frame — visibly unaligned with the preview. Capping the height keeps the
/// guide inset on every device and aspect, and 0.75 lands the bottom edge in
/// the same place the card aspect always used, clear of the shutter.
const double kDocumentGuideMaxHeightFraction = 0.75;

/// The guide rectangle inside a viewfinder of [size] for a document of
/// [aspect] (width / height).
///
/// Fits BOTH dimensions: width-led, then height-capped, preserving [aspect]
/// either way so the crop keeps the document's true proportions.
Rect documentGuideRect(Size size, double aspect) {
  var width = size.width * kDocumentGuideWidthFraction;
  var height = width / aspect;

  final maxHeight = size.height * kDocumentGuideMaxHeightFraction;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspect;
  }

  return Rect.fromLTWH(
    (size.width - width) / 2,
    (size.height - height) / 2 - kDocumentGuideTopShift,
    width,
    height,
  );
}

/// Centre of the guide — handy for callers that only need the focus point.
Offset documentGuideCenter(Size size, double aspect) =>
    documentGuideRect(size, aspect).center;

// ─── Document aspect ratios ───────────────────────────────────────────────────
//
// Passport pages are squarer than ID cards, and a card-shaped crop clips the
// MRZ band off the bottom of a passport.

/// ISO/IEC 7810 ID-1 (85.6 mm × 53.98 mm).
const double kCardGuideAspect = 1.586;
const double kPassportGuideAspect = 1.42;

double documentGuideAspect(IdTypeConfig idType) =>
    idType.key == 'passport' ? kPassportGuideAspect : kCardGuideAspect;
