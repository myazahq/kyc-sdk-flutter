import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_math.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_store.dart';

// The on-device presence math — what decides whether a fix counts as "at the
// address" and what local day/night it lands on. This is the whole privacy
// contract: only these DERIVED values ever leave the phone. A port of the RN
// SDK's presence.test.ts — keep the two in lockstep.

void main() {
  _pinTtl();
  group('haversineMeters', () {
    test('zero distance for the same point', () {
      expect(haversineMeters(6.4281, 3.4219, 6.4281, 3.4219), 0);
    });

    test('roughly 111 km per degree of latitude', () {
      final d = haversineMeters(6, 3, 7, 3);
      expect(d, greaterThan(110000));
      expect(d, lessThan(112500));
    });
  });

  group('insideFence', () {
    test('a fix at the pin is inside', () {
      expect(
        insideFence(pinLat: 6.4281, pinLng: 3.4219, fixLat: 6.4281, fixLng: 3.4219, accuracy: 10),
        isTrue,
      );
    });

    test('a fix about 180 m away is inside the 250 m base radius', () {
      expect(
        insideFence(pinLat: 6.4281, pinLng: 3.4219, fixLat: 6.4297, fixLng: 3.4219, accuracy: 10),
        isTrue,
      );
    });

    test('a fix about 2 km away is outside', () {
      expect(
        insideFence(pinLat: 6.4281, pinLng: 3.4219, fixLat: 6.4461, fixLng: 3.4219, accuracy: 10),
        isFalse,
      );
    });

    test('poor accuracy widens the fence, capped at 1 km', () {
      expect(
        insideFence(pinLat: 6.4281, pinLng: 3.4219, fixLat: 6.4361, fixLng: 3.4219, accuracy: 950),
        isTrue,
      );
      expect(
        insideFence(pinLat: 6.4281, pinLng: 3.4219, fixLat: 6.4471, fixLng: 3.4219, accuracy: 5000),
        isFalse,
      );
    });
  });

  group('localDayAndNight', () {
    test('formats the device-local day and flags the night band', () {
      final night = localDayAndNight(DateTime(2026, 8, 20, 22, 30));
      expect(night.day, '2026-08-20');
      expect(night.nightPresent, isTrue);

      final morning = localDayAndNight(DateTime(2026, 8, 20, 9));
      expect(morning.nightPresent, isFalse);

      final smallHours = localDayAndNight(DateTime(2026, 8, 21, 2));
      expect(smallHours.day, '2026-08-21');
      expect(smallHours.nightPresent, isTrue);
    });
  });
}

void _pinTtl() {
  group('pinExpiredAt', () {
    final now = DateTime.utc(2026, 8, 31);
    String daysAgo(int d) => now.subtract(Duration(days: d)).toIso8601String();

    test('keeps a pin alive through the whole plausible watch lifetime', () {
      expect(pinExpiredAt(daysAgo(44), now), isFalse);
      // Exactly the boundary is still alive: expiry is strictly past the TTL,
      // and the RN mirror compares the same way.
      expect(pinExpiredAt(daysAgo(kPinTtlDays), now), isFalse);
    });

    test('expires a pin past the TTL so the device stops sampling location', () {
      expect(pinExpiredAt(daysAgo(kPinTtlDays + 1), now), isTrue);
    });

    test('treats an unparseable stamp as expired, never as immortal', () {
      expect(pinExpiredAt('garbage', now), isTrue);
      expect(pinExpiredAt('', now), isTrue);
    });
  });
}
