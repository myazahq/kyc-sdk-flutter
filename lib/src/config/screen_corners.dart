import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

// Apple's grammar for nested corners is CONCENTRIC: an inset card's radius is
// the DISPLAY's corner radius minus the gap between card and screen edge —
// that is why the system share sheet's curve runs parallel to the phone's.
// No public API exposes the display radius, so iOS resolves it from the
// model's logical screen size (the per-device values Apple ships, from
// UIScreen's private _displayCornerRadius, in points). Unknown hardware falls
// back on whether the display is rounded at all: home-indicator devices are,
// square-corner devices are not. Mirrors the RN SDK's screen-corners.ts.

/// `short x long` logical points → display corner radius in points.
const Map<String, double> _iosRadii = {
  // X / XS / 11 Pro are 39 on the same canvas as the 12–13 mini's 44; the
  // minis are the ones still in pockets, so the shared key takes their value.
  '375x812': 44,
  '414x896': 41.5, // XR / 11 / XS Max / 11 Pro Max
  '390x844': 47.33, // 12 / 12 Pro / 13 / 13 Pro / 14
  '428x926': 53.33, // 12–13 Pro Max / 14 Plus
  '393x852': 55, // 14 Pro / 15 / 15 Pro / 16 / 16e
  '430x932': 55, // 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus
  '402x874': 62, // 16 Pro
  '440x956': 62, // 16 Pro Max
};

/// The display's own corner radius, in logical points/dp. 0 means a
/// square-cornered screen (or one we cannot judge), and the caller picks its
/// flat-world look instead.
double displayCornerRadius(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final shortSide = size.shortestSide.round();
  final longSide = size.longestSide.round();
  final key = '${shortSide}x$longSide';
  final bottomInset = MediaQuery.paddingOf(context).bottom;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final known = _iosRadii[key];
    if (known != null) return known;
    // Unlisted model: a home indicator means a rounded display; 47 is the
    // middle of the modern range.
    return bottomInset > 0 ? 47 : 0;
  }

  // Android has no cheap signal (the RoundedCorner API needs a plugin). A
  // small bottom inset is gesture navigation — overwhelmingly the modern,
  // rounded-display phones — while ~48dp is the opaque 3-button bar, which
  // says nothing. Modest on purpose: an under-estimate still looks composed,
  // an over-estimate looks like a mistake.
  return bottomInset > 0 && bottomInset <= 32 ? 32 : 0;
}
