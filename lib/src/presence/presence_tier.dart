// ─── Which presence tier is ACTUALLY running ─────────────────────────────────
//
// One pure decision, so the answer presenceStatus() gives can be pinned
// without a device, and so the RN mirror (presence/tier.ts) can be held to
// the same table.
//
// The location-services toggle sits ABOVE every permission: with services
// off, a granted permission and an armed fence produce no fix and no
// transition, so nothing is running whatever the grants say. That was the
// silent case (permission granted, toggle off, `noFix` forever), and it is
// why the switch is a first-class input here rather than folded into one of
// the permission states.

enum PresenceTier { background, foreground, none }

enum PresencePermission { granted, denied, undetermined }

class PresenceTierInputs {
  final bool pinStored;
  final bool locationServicesEnabled;
  final PresencePermission foregroundPermission;
  final PresencePermission backgroundPermission;

  /// The native geofence is registered right now.
  final bool geofenceArmed;

  /// The Android foreground service is running right now.
  final bool foregroundServiceRunning;

  const PresenceTierInputs({
    required this.pinStored,
    required this.locationServicesEnabled,
    required this.foregroundPermission,
    required this.backgroundPermission,
    required this.geofenceArmed,
    required this.foregroundServiceRunning,
  });
}

PresenceTier resolvePresenceTier(PresenceTierInputs i) {
  if (!i.pinStored || !i.locationServicesEnabled) return PresenceTier.none;
  if (i.backgroundPermission == PresencePermission.granted &&
      (i.geofenceArmed || i.foregroundServiceRunning)) {
    return PresenceTier.background;
  }
  if (i.foregroundPermission == PresencePermission.granted) {
    return PresenceTier.foreground;
  }
  return PresenceTier.none;
}
