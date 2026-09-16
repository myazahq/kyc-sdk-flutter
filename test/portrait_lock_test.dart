import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Portrait is a flow-wide rule, not a screen's habit ──────────────────────
//
// Every host that mounts a camera step must pin the display upright: on Android
// the preview follows the display, so a rotation mid-capture flips the feed.
// The KYC flow did it inline and the since-deleted face re-authentication host,
// which ran the SAME liveness screen, did nothing at all (2026-09-16).
//
// There is ONE host today, and that is the point: a second entry point is
// exactly how the two drifted before. This is a SOURCE scan because the defect
// is an omission at a call site — a new host that forgets the mixin compiles,
// runs, and only misbehaves on a device somebody happens to tilt.

const _hosts = [
  'lib/src/widgets/myaza_kyc_widget.dart',
];

void main() {
  test('every host that mounts a flow step pins portrait', () {
    for (final path in _hosts) {
      expect(
        File(path).readAsStringSync(),
        contains('with PortraitLock'),
        reason: '$path mounts a camera step, so it must mount PortraitLock',
      );
    }
  });

  test('the orientation calls live in exactly one file', () {
    final offenders = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('utils/portrait_lock.dart'))
        .where((f) => f.readAsStringSync().contains('setPreferredOrientations'))
        .map((f) => f.path)
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: 'set orientations through PortraitLock, or two hosts will drift',
    );
  });
}
