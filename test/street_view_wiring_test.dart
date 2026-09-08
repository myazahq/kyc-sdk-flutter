import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Street View reaches every SDK through ONE protocol ──────────────────────
//
// The hosted /embed/street-view page speaks one vocabulary and the three
// map-frame mirrors (web, RN, Flutter) must all understand it: a token missing
// from one mirror is a platform where the entrance step silently falls back to
// the photo. Read across the monorepo, the way the RN foldVectors test reads
// this package's fixture. The second group pins this SDK's own wiring.

const _mirrors = {
  'web': '../kyc-sdk-react/src/lib/map-frame.ts',
  'rn': '../kyc-sdk-react-native/src/lib/map-frame.ts',
  'flutter': 'lib/src/config/street_view_frame.dart',
};

void main() {
  group('the street-view protocol is mirrored on every SDK', () {
    for (final entry in _mirrors.entries) {
      test('${entry.key} carries every page message and the page path', () {
        final source = File(entry.value).readAsStringSync();
        for (final token in [
          'sv-ready',
          'sv-unavailable',
          'sv-pov',
          'panoId',
          'viewFov',
          '/embed/street-view',
        ]) {
          expect(source, contains(token), reason: '${entry.key}: $token');
        }
      });
    }
  });

  group('this SDK offers the framed street view', () {
    test('the entrance step renders FramedStreetView and falls back to the photo',
        () {
      final step = File('lib/src/screens/address/address_entrance_step.dart')
          .readAsStringSync();
      expect(step, contains("import 'framed_street_view.dart';"));
      expect(step, contains('FramedStreetView('));
      expect(step, contains('onUnavailable:'));
      expect(step, contains('streetViewFrameUrlOf('));
    });

    test('the flow model derives the offer from the maps frame URL', () {
      final order = File('lib/src/providers/address_step_order.dart')
          .readAsStringSync();
      expect(order,
          contains('hasStreetViewFrame: state.serverConfig.mapsFrameUrl != null'));
    });

    test('the entrance step fills the viewport so its actions can stick', () {
      final shell =
          File('lib/src/widgets/myaza_kyc_widget.dart').readAsStringSync();
      expect(shell, contains('step == KYCStep.addressEntrance'));
    });
  });
}
