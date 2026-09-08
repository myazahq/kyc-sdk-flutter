import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/location_service.dart';

// ─── The attest fix falls back on the one the flow already took ────────────
//
// A confirm-time read that times out must not cost the submission its device
// fix when "Use my location" placed the pin on one a minute earlier. Fresh
// wins; a recent real fix stands in; a stale or mocked one never does.
// Mirrors RN's deviceFixFallback.test.ts.

DeviceFix at(DateTime now, Duration age, {bool? mocked}) => DeviceFix(
      lat: 4.93,
      lng: 8.32,
      accuracy: 12,
      timestamp: now.subtract(age),
      mocked: mocked,
    );

void main() {
  final now = DateTime(2026, 9, 7, 8);

  test('prefers the fresh read', () {
    final fresh = at(now, Duration.zero);
    expect(pickDeviceFix(fresh, at(now, const Duration(seconds: 30)), now: now), same(fresh));
  });

  test('falls back on a recent fix from earlier in the flow', () {
    final recent = at(now, const Duration(minutes: 1));
    expect(pickDeviceFix(null, recent, now: now), same(recent));
  });

  test('never sends a stale or mocked fix', () {
    expect(pickDeviceFix(null, at(now, kRecentFixMaxAge + const Duration(seconds: 1)), now: now), isNull);
    expect(pickDeviceFix(null, at(now, const Duration(seconds: 10), mocked: true), now: now), isNull);
    expect(pickDeviceFix(null, null, now: now), isNull);
  });
}
