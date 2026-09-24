import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The icon set reaches the SDK through one directory.
///
/// Its whole value is that an icon means the same thing and is drawn the same
/// way everywhere, which only holds while call sites go through the boundary.
/// A direct `package:hugeicons` import compiles perfectly and quietly opts that
/// file out of the shared stroke weight and the shared names, so it has to be
/// caught here rather than in review.
void main() {
  const boundary = 'lib/src/widgets/icons/';

  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('scans the real source tree', () {
    // Without this the two tests below pass triumphantly on an empty list if
    // the layout ever moves.
    expect(sources.length, greaterThan(100));
  });

  test('only the icon boundary imports the icon package', () {
    final offenders = sources
        .where((f) => !f.path.replaceAll(r'\', '/').startsWith(boundary))
        .where((f) => f.readAsStringSync().contains("package:hugeicons"))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason:
            'import ../widgets/icons/icons.dart and use MyazaIcons instead');
  });

  test('nothing imports the retired icon package', () {
    final offenders = sources
        .where((f) => f.readAsStringSync().contains('lucide_icons_flutter'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
