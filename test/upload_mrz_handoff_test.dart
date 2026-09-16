import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── An uploaded passport's MRZ reaches the chip step ────────────────────────
//
// A photo picked on the document step has its MRZ read in the background. On
// Android the fetched text model makes that read slower than a tap on
// Continue, and the read used to stop the moment the screen unmounted: the
// chip step then mounted with no MRZ and opened its own camera scanner, which
// sat on a spinner (2026-09-15). iOS finished the read first, so it worked
// there. Two halves keep it working: the read survives the screen, and the
// chip step takes a code that lands after it has mounted.
//
// Pinned against the source because neither half can fail loudly: a dropped
// read and a missed late code both just look like "the chip step wants a scan".

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing $signature');
  // The next method at class indentation ends this one.
  final end = source.indexOf('\n  }\n', start);
  return source.substring(start, end);
}

void main() {
  test('the upload read outlives the document screen', () {
    final source =
        File('lib/src/screens/document_capture_screen.dart').readAsStringSync();
    final body = _body(source, 'void _maybeReadMrz(');
    final capture = body.indexOf('final notifier = ref.read(kYCNotifierProvider.notifier);');
    expect(capture, isNot(-1), reason: 'the notifier must be taken before the read starts');
    expect(capture, lessThan(body.indexOf('unawaited(')));
    final read = body.substring(body.indexOf('unawaited('));
    expect(read.contains('if (!mounted) return;'), isFalse,
        reason: 'unmounting must not abandon the read');
    expect(read.contains('ref.read('), isFalse,
        reason: '`ref` is unusable once the screen is disposed');
    expect(read, contains('notifier.setMrzScan(scan);'));
  });

  test('the chip step takes a code that lands after it mounted', () {
    final source = File('lib/src/screens/nfc_screen.dart').readAsStringSync();
    expect(source, contains('ref.listen(kYCNotifierProvider.select((s) => s.mrzScan)'));
    expect(source, contains('_phase == _Phase.scanning'));
  });

  test('the chip camera view watches the camera before the model gate', () {
    // The camera provider is auto-disposed. Watched only once the text model
    // was ready, the instance _start() initialised was thrown away, and the
    // spinner watched a fresh one that never became ready.
    final source = File('lib/src/screens/mrz_scan_view.dart').readAsStringSync();
    final build = source.substring(source.indexOf('Widget build(BuildContext context)'));
    final watch = build.indexOf('ref.watch(cameraNotifierProvider)');
    expect(watch, isNot(-1));
    expect(watch, lessThan(build.indexOf('switch (_textModel.state.value)')));
  });
}
