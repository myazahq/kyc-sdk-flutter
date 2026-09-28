import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Silent capture is taken on document capture only ───────────────────────
//
// A source check, because the rule is about WHERE frames are taken and no
// input makes a grab in the wrong place throw: the liveness screen must take
// none, and the document review must open the front camera for its frame.

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the liveness screen takes no silent frames', () {
    final src = read('lib/src/screens/liveness_screen.dart');
    expect(src.contains(RegExp('captureSilently|silent_capture|SilentCapture')), isFalse);
  });

  test('the document review opens the front camera for one', () {
    final src = read('lib/src/screens/document_capture_screen.dart');
    expect(src, contains('grabSilentFrontFrame('));
    expect(src, contains('SilentCaptureMoment.document'));
    expect(src, contains('if (phase == _ScanPhase.review) unawaited(_takeSilentFrontFrame());'));
  });
}
