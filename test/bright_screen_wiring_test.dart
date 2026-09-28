import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── The bright screen, wired into the flow ───────────────────────────────────
//
// The rules are pinned in bright_screen_test.dart; these pin the seams that
// carry them, since a missing call compiles, passes and simply never lights
// the face (or leaves a white baseline under the flash).

String _source(String path) => File(path).readAsStringSync();

void main() {
  test('the liveness screen publishes its camera and paints a black baseline', () {
    final screen = _source('lib/src/screens/liveness_screen.dart');
    expect(screen, contains('livenessCameraRunning('));
    // Latched from the camera screen, so the review after it stays lit.
    expect(screen, contains('livenessStepLit('));
    expect(screen, contains('pastPrimers: _ready && !_showPrimer'));
    expect(screen, contains('livenessCameraOnProvider'));
    expect(screen, contains('flashOverlayColor('));
    expect(screen, contains('_flashSequenceRunning.value = true'));
  });

  test('the flow lights itself from that, and holds the screen bright', () {
    final flow = _source('lib/src/widgets/myaza_kyc_widget.dart');
    expect(flow, contains('livenessBrightScreenActive('));
    expect(flow, contains('config.livenessBrightScreen'));
    expect(flow, contains('BrightScreenBoost('));
    expect(flow, contains('blendBrightScreen('));
    // The toggle cannot act while the flow is held light, so it is hidden.
    expect(flow, contains('config.showThemeToggle && !brightScreen'));
  });

  test('the camera flag is scoped per flow', () {
    final scope = _source('lib/src/widgets/kyc_flow_scope.dart');
    expect(scope, contains('livenessCameraOnProvider.overrideWith'));
  });
}
