import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/map_frame.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/street_view_fov.dart';

// A port of the web SDK's street-view-fov.test.ts and the RN twin. The three
// implementations must agree, because a frame captured on one platform is
// fetched by the server for all of them.

void main() {
  group('frameFov', () {
    test('a full-width frame captures the full viewport', () {
      expect(frameFov(90, 1), closeTo(90, 1e-6));
    });

    test('an entrance-sized frame captures the slice it subtends', () {
      // 58% of a 90-degree view: 2·atan(0.58·tan(45°)) ≈ 60.23°, NOT 52.2°:
      // the mapping is tan-linear, not angle-linear.
      expect(frameFov(90, 0.58), closeTo(60.23, 0.05));
    });

    test('is monotonic: a smaller frame never widens the shot', () {
      expect(frameFov(90, 0.4), lessThan(frameFov(90, 0.6)));
      expect(frameFov(120, 0.5), lessThan(120));
    });

    test('an unmeasurable fraction is floored, never zero or negative fov', () {
      expect(frameFov(90, 0), greaterThan(0));
      expect(frameFov(90, -3), greaterThan(0));
    });
  });

  group('captureStreetViewFrame', () {
    const pov = StreetViewPov(panoId: 'p1', heading: 12.5, pitch: 3, viewFov: 90);

    test('stores the slice the frame subtends when both widths are known', () {
      final frame = captureStreetViewFrame(pov, 58, 100);
      expect(frame.panoId, 'p1');
      expect(frame.heading, 12.5);
      expect(frame.fov, closeTo(60.23, 0.05));
    });

    test('falls back to the whole view when a width is unmeasured, and clamps',
        () {
      expect(captureStreetViewFrame(pov, 0, 100).fov, 90);
      final wide = captureStreetViewFrame(
          const StreetViewPov(panoId: 'p1', heading: 1, pitch: 140, viewFov: 200),
          0,
          0);
      expect(wide.pitch, 90);
      expect(wide.fov, 120);
      expect(
          captureStreetViewFrame(
                  const StreetViewPov(panoId: 'p1', heading: 1, pitch: -140, viewFov: 4),
                  0,
                  0)
              .fov,
          10);
    });
  });
}
