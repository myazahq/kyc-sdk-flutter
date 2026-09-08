import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_tier.dart';

// The one table behind presenceStatus().tier. A port of the RN SDK's
// presenceTier.test.ts — keep the two in lockstep.

const _base = PresenceTierInputs(
  pinStored: true,
  locationServicesEnabled: true,
  foregroundPermission: PresencePermission.granted,
  backgroundPermission: PresencePermission.granted,
  geofenceArmed: true,
  foregroundServiceRunning: false,
);

PresenceTierInputs _with({
  bool? pinStored,
  bool? locationServicesEnabled,
  PresencePermission? foregroundPermission,
  PresencePermission? backgroundPermission,
  bool? geofenceArmed,
  bool? foregroundServiceRunning,
}) =>
    PresenceTierInputs(
      pinStored: pinStored ?? _base.pinStored,
      locationServicesEnabled: locationServicesEnabled ?? _base.locationServicesEnabled,
      foregroundPermission: foregroundPermission ?? _base.foregroundPermission,
      backgroundPermission: backgroundPermission ?? _base.backgroundPermission,
      geofenceArmed: geofenceArmed ?? _base.geofenceArmed,
      foregroundServiceRunning: foregroundServiceRunning ?? _base.foregroundServiceRunning,
    );

void main() {
  group('resolvePresenceTier', () {
    test('background when the always grant is in and something is armed', () {
      expect(resolvePresenceTier(_base), PresenceTier.background);
      expect(
        resolvePresenceTier(_with(geofenceArmed: false, foregroundServiceRunning: true)),
        PresenceTier.background,
      );
    });

    test('foreground when only the while-in-use grant is in, or nothing is armed', () {
      expect(
        resolvePresenceTier(_with(backgroundPermission: PresencePermission.denied)),
        PresenceTier.foreground,
      );
      expect(resolvePresenceTier(_with(geofenceArmed: false)), PresenceTier.foreground);
    });

    test('none without a pin, or without any grant', () {
      expect(resolvePresenceTier(_with(pinStored: false)), PresenceTier.none);
      expect(
        resolvePresenceTier(_with(
          foregroundPermission: PresencePermission.denied,
          backgroundPermission: PresencePermission.denied,
        )),
        PresenceTier.none,
      );
    });

    test('none when location services are OFF, whatever the grants say', () {
      // The silent case: permission granted, toggle off, no fix ever. The
      // switch outranks every permission because nothing can run without it.
      expect(resolvePresenceTier(_with(locationServicesEnabled: false)), PresenceTier.none);
    });
  });
}
