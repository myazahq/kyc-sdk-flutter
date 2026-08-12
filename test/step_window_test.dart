import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/step_window.dart';

/// Readable rendering of a slot row, for assertions that read like the UI.
String render(int total, int active, int max) => windowedSteps(
      total,
      active,
      maxCircles: max,
    ).map((s) => s == kStepEllipsis ? '…' : '${s + 1}').join(' ');

// Real device widths, minus the row's 16dp padding each side.
const smallAndroid = 360.0 - 32; // 328
const iPhoneProMax = 430.0 - 32; // 398
const tiny = 320.0 - 32; // 288

void main() {
  group('fitStepCircles', () {
    test('fits more circles on wider screens', () {
      expect(fitStepCircles(tiny, 26), 7);
      expect(fitStepCircles(smallAndroid, 26), 8);
      expect(fitStepCircles(iPhoneProMax, 26), 9);
    });

    test('reports 0 for an unmeasured width, which means "render them all"', () {
      expect(fitStepCircles(0, 26), 0);
      expect(fitStepCircles(double.nan, 26), 0);
      expect(fitStepCircles(-100, 26), 0);
    });

    test('fits fewer circles once the system text size grows them', () {
      expect(fitStepCircles(smallAndroid, 36), lessThan(fitStepCircles(smallAndroid, 26)));
    });
  });

  group('windowedSteps', () {
    test('shows every step when they fit, however many that is', () {
      expect(render(4, 1, 9), '1 2 3 4');
      expect(render(8, 3, 9), '1 2 3 4 5 6 7 8');
    });

    test('renders everything when the width is not known yet', () {
      expect(render(12, 5, 0), '1 2 3 4 5 6 7 8 9 10 11 12');
    });

    test('collapses only once the steps would stop fitting', () {
      // The same 9-step flow, on two phones: the wider one shows all of it, the
      // narrower one collapses. A fixed cap would have collapsed both.
      expect(render(9, 4, fitStepCircles(iPhoneProMax, 26)), '1 2 3 4 5 6 7 8 9');
      expect(render(9, 4, fitStepCircles(smallAndroid, 26)), '1 … 4 5 6 7 … 9');
    });

    test('always shows first and last, so the total is never hidden', () {
      for (var total = 6; total <= 16; total++) {
        for (var active = 0; active < total; active++) {
          for (final max in [5, 7, 9, 11]) {
            final slots = windowedSteps(total, active, maxCircles: max);
            expect(slots.first, 0);
            expect(slots.last, total - 1);
          }
        }
      }
    });

    test('always contains the current step', () {
      for (var total = 6; total <= 16; total++) {
        for (var active = 0; active < total; active++) {
          for (final max in [5, 7, 9, 11]) {
            expect(windowedSteps(total, active, maxCircles: max), contains(active));
          }
        }
      }
    });

    test('never draws more circles than fit', () {
      for (var total = 1; total <= 20; total++) {
        for (var active = 0; active < total; active++) {
          for (final max in [5, 7, 9, 11]) {
            final circles = windowedSteps(total, active, maxCircles: max)
                .where((s) => s != kStepEllipsis)
                .length;
            expect(circles, lessThanOrEqualTo(max < 5 ? 5 : max));
          }
        }
      }
    });

    test('keeps slots strictly ascending with no duplicates', () {
      for (var total = 1; total <= 20; total++) {
        for (var active = 0; active < total; active++) {
          for (final max in [5, 7, 9]) {
            final nums = windowedSteps(total, active, maxCircles: max)
                .where((s) => s != kStepEllipsis)
                .toList();
            expect(nums, orderedEquals([...nums]..sort()));
            expect(nums.toSet().length, nums.length);
          }
        }
      }
    });

    test('survives nonsense input rather than rendering a broken row', () {
      expect(windowedSteps(0, 0, maxCircles: 9), isEmpty);
      expect(windowedSteps(-3, 2, maxCircles: 9), isEmpty);
      expect(render(12, 99, 7), '1 … 9 10 11 12');
      expect(render(12, -5, 7), '1 2 3 4 … 12');
    });

    test('matches the React Native implementation exactly', () {
      // The two SDKs must window identically or the same workflow looks
      // different on each. These strings were COMPUTED by running the RN
      // implementation, not transcribed: the first version of this test was
      // hand-copied from an older RN build and failed against correct Dart.
      expect(render(10, 5, 8), '1 … 5 6 7 8 … 10');
      expect(render(12, 0, 7), '1 2 3 4 … 12');
      expect(render(12, 11, 7), '1 … 9 10 11 12');
      expect(render(9, 4, 8), '1 … 4 5 6 7 … 9');
      expect(render(14, 6, 9), '1 … 5 6 7 8 9 … 14');
    });
  });
}
