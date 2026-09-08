import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/location_failure.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/address_current_location.dart';

// ─── Location failures are CLASSIFIED ────────────────────────────────────────
//
// A refused permission, a phone with location switched off, and a fix that
// took too long are three problems with three remedies; the copy names the
// right one, and every line ends with the manual pin, which always works.

void main() {
  const reasons = [
    LocationFailure.denied,
    LocationFailure.unavailable,
    LocationFailure.timeout,
    LocationFailure.unsupported,
    null,
  ];

  test('names a different remedy per reason, always ending with the manual pin',
      () {
    final messages = reasons.map(locationFailureMessage).toList();
    expect(messages.take(4).toSet().length, 4);
    for (final m in messages) {
      expect(m, matches(RegExp(r'place the pin yourself\.$', caseSensitive: false)));
    }
    expect(locationFailureMessage(LocationFailure.denied), contains('Settings'));
    expect(locationFailureMessage(LocationFailure.unavailable),
        contains('switched on'));
    expect(locationFailureMessage(null),
        locationFailureMessage(LocationFailure.unsupported));
  });

  test('carries no em dash and reads in UK English', () {
    for (final r in reasons) {
      final m = locationFailureMessage(r);
      expect(m, isNot(contains('—')));
      expect(m, isNot(matches(RegExp(r'\bcenter\b|\bcolor\b'))));
    }
  });

  test('a device with no location plugin records unsupported, never a crash',
      () async {
    // The test host has no platform channel behind geolocator, which is the
    // same shape as a device that cannot answer at all.
    resetCurrentFix();
    final api = KYCApiService(baseUrl: 'https://api.example', apiKey: 'pk_test_x');
    expect(await prefetchCurrentFix(api), isNull);
    expect(currentFixFailure(), isNotNull);
    resetCurrentFix();
    expect(currentFixFailure(), isNull);
  });

  test('the pin actions use the classified message', () {
    final actions = _read('screens/address/address_pin_actions.dart');
    expect(actions, contains('locationFailureMessage(currentFixFailure())'));
    expect(actions, isNot(contains('kAddressLocateFailed')));
  });
}

String _read(String rel) => File('lib/src/$rel').readAsStringSync();
