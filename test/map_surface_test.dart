import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';

// ─── The pin step's map height and its reachable Continue ────────────────────
//
// The four numbers are the web SDK's (`h-[40vh] min-h-[240px] max-h-[360px]
// sm:h-[420px]`), ported here and to RN; a change on one platform is a change
// on all three. The second group pins the WIRING: the pin step's actions must
// ride StickyActions inside a viewport-filling sheet, or on a short phone the
// map swallows every drag and Continue is unreachable.

void main() {
  group('mapSurfaceHeight', () {
    test('gives a phone 40% of its height, floored at 240', () {
      expect(mapSurfaceHeight(const Size(390, 500)), 240);
      expect(mapSurfaceHeight(const Size(390, 700)), 280);
    });

    test('caps a tall phone at 360', () {
      expect(mapSurfaceHeight(const Size(430, 932)), 360);
    });

    test('is a flat 420 from the wide breakpoint', () {
      expect(mapSurfaceHeight(const Size(640, 500)), 420);
      expect(mapSurfaceHeight(const Size(1024, 1366)), 420);
    });

    test('carries the web numbers', () {
      expect(kMapSurfacePhoneFraction, 0.4);
      expect(kMapSurfacePhoneMin, 240);
      expect(kMapSurfacePhoneMax, 360);
      expect(kMapSurfaceWideBreakpoint, 640);
      expect(kMapSurfaceWide, 420);
    });
  });

  group('the pin step holds its actions at the bottom of a filled viewport', () {
    test('wraps its body in StickyActions and sizes the map by the rule', () {
      final step = File('lib/src/screens/address/address_pin_step.dart')
          .readAsStringSync();
      expect(step, contains("import '../../widgets/sticky_actions.dart';"));
      expect(step, contains('StickyActions('));
      expect(step, contains('mapSurfaceHeight('));
    });

    test('is listed among the steps the sheet lets fill the viewport', () {
      final shell = File('lib/src/widgets/myaza_kyc_widget.dart')
          .readAsStringSync();
      expect(shell, contains('step == KYCStep.addressCollection'));
    });
  });
}
