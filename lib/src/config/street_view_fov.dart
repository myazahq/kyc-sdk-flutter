import 'dart:math' as math;

import 'address_state.dart' show AddressStreetView;
import 'map_frame.dart' show StreetViewPov;

// ─── The Street View entrance frame's maths ──────────────────────────────────
//
// A mirror of the web SDK's StreetViewFramer `frameFov` and the RN
// street-view-fov.ts; keep the three in lockstep.

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

/// The field of view a centred sub-frame of the viewport actually subtends.
///
/// The frame is entrance-sized guidance, so the STORED image must be what the
/// frame showed, not the whole panorama: otherwise "fit your gate in the
/// frame" captures a streetscape with the gate somewhere in it. Exact
/// projection maths (a perspective view is a flat plane, so a width fraction
/// maps through tan, not linearly).
double frameFov(double viewportFovDeg, double widthFraction) {
  final fraction = _clamp(widthFraction, 0.1, 1);
  final half = viewportFovDeg * math.pi / 360;
  return 2 * math.atan(fraction * math.tan(half)) * 180 / math.pi;
}

/// The frame to store for a reported view: the slice the frame subtends when
/// both widths are known, else the whole view; fov 10..120, pitch ±90.
AddressStreetView captureStreetViewFrame(
  StreetViewPov pov,
  double frameWidth,
  double viewWidth,
) {
  final fov = frameWidth > 0 && viewWidth > 0
      ? _clamp(frameFov(pov.viewFov, frameWidth / viewWidth), 10, 120)
      : _clamp(pov.viewFov, 10, 120);
  return AddressStreetView(
    panoId: pov.panoId,
    heading: pov.heading,
    pitch: _clamp(pov.pitch, -90, 90),
    fov: fov,
  );
}
