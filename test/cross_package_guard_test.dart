import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── A test that reads another package skips when that package is absent ─────
//
// The public mirror (myazahq/kyc-sdk-flutter) carries this package alone. A
// test that reaches into kyc-sdk-react or kyc-sdk-react-native by a relative
// path passes here and fails there, which is how the 2.7.0 publish was refused.
// Such a test guards each sibling read with `existsSync()` and a `skip:`; this
// pins that every one does.

void main() {
  test('every sibling read is guarded with existsSync and skip', () {
    final suites = Directory('test')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => !f.path.endsWith('cross_package_guard_test.dart'));
    for (final file in suites) {
      final source = file.readAsStringSync();
      if (!source.contains('../kyc-sdk-')) continue;
      expect(source, contains('.existsSync()'), reason: file.path);
      expect(source, contains('skip:'), reason: file.path);
    }
  });
}
