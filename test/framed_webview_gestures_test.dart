import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── A map inside a scroll view still moves on Android ──────────────────────
//
// The framed map and the framed Street View are WebViews inside StickyActions'
// scroll view, and in Flutter's gesture arena the scroll view wins a vertical
// drag unless the WebView claims it eagerly (Galaxy S24, 2026-09-07).

void main() {
  for (final rel in [
    'lib/src/widgets/framed_map_picker.dart',
    'lib/src/screens/address/framed_street_view.dart',
  ]) {
    test('$rel claims its drags with an eager recogniser', () {
      final source = File(rel).readAsStringSync();
      expect(source, contains('EagerGestureRecognizer'));
      expect(source, contains('gestureRecognizers'));
    });
  }
}
