import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/background_presence.dart';

// iOS answers the "Always" request natively (PresenceAlwaysPermission.swift);
// this is how that answer becomes the permission enable() decides on.

void main() {
  const current = LocationPermission.whileInUse;

  test('each native answer maps to its permission', () {
    expect(alwaysAnswerToPermission('always', current), LocationPermission.always);
    expect(alwaysAnswerToPermission('whileInUse', current), LocationPermission.whileInUse);
    expect(alwaysAnswerToPermission('denied', current), LocationPermission.deniedForever);
  });

  test('no answer, or one this build does not know, keeps what was held', () {
    expect(alwaysAnswerToPermission(null, current), current);
    expect(alwaysAnswerToPermission('undetermined', current), current);
    expect(alwaysAnswerToPermission('provisional', current), current);
  });
}
