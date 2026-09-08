import 'package:geolocator/geolocator.dart';

import 'background_presence.dart';
import 'foreground_presence.dart';
import 'presence_store.dart';
import 'presence_tier.dart';

export 'presence_tier.dart' show PresencePermission, PresenceTier;

// ─── Tier visibility + recovery ──────────────────────────────────────────────
//
// A revoked permission silently downgrades the presence tier, and "silently"
// is the defect: the host app cannot ask the person to restore what it does
// not know is gone. presenceStatus() answers "which tier is actually running
// for this user?", and openLocationSettings() is the only honest recovery
// path, since neither OS allows re-prompting in-app after a denial. Mirrors
// the RN SDK's presence/status.ts; keep the two shapes in lockstep.
//
// The phone's LOCATION SERVICES toggle is checked as well as the permissions.
// Permission granted with the toggle off produced `noFix` on every report and
// nothing said why; OkHi's integration guidance calls this out for the same
// reason. It is a first-class input to the tier (presence_tier.dart).

class PresenceStatus {
  /// The tier that is ACTUALLY running, not the one that was asked for.
  final PresenceTier tier;

  /// Whether a pin is stored for this user (without one, no tier can run).
  final bool pinStored;

  /// Whether the stored pin is the always-on arrangement.
  final bool alwaysOn;

  /// The phone's location services switch. Off, nothing can run whatever the
  /// permissions say; `openLocationSettings(target: services)` is the road back.
  final bool locationServicesEnabled;
  final PresencePermission foregroundPermission;
  final PresencePermission backgroundPermission;

  /// The native geofence is registered with the OS right now.
  final bool geofenceArmed;

  /// The Android foreground service is running right now (always false on iOS).
  final bool foregroundServiceRunning;

  const PresenceStatus({
    required this.tier,
    required this.pinStored,
    required this.alwaysOn,
    required this.locationServicesEnabled,
    required this.foregroundPermission,
    required this.backgroundPermission,
    required this.geofenceArmed,
    required this.foregroundServiceRunning,
  });
}

PresencePermission _foreground(LocationPermission p) {
  switch (p) {
    case LocationPermission.always:
    case LocationPermission.whileInUse:
      return PresencePermission.granted;
    case LocationPermission.denied:
    case LocationPermission.deniedForever:
      return PresencePermission.denied;
    case LocationPermission.unableToDetermine:
      return PresencePermission.undetermined;
  }
}

PresencePermission _background(LocationPermission p) {
  switch (p) {
    case LocationPermission.always:
      return PresencePermission.granted;
    case LocationPermission.whileInUse:
    case LocationPermission.denied:
    case LocationPermission.deniedForever:
      return PresencePermission.denied;
    case LocationPermission.unableToDetermine:
      return PresencePermission.undetermined;
  }
}

/// Which presence tier is actually running for [externalUserId]. Never throws.
Future<PresenceStatus> presenceStatus(String externalUserId) async {
  final pin = await loadPresencePin(externalUserId);
  LocationPermission permission = LocationPermission.unableToDetermine;
  // An unanswerable services check reads as ON: the permissions still gate,
  // and a false "off" would send people to Settings for nothing.
  bool services = true;
  try {
    permission = await Geolocator.checkPermission();
    services = await Geolocator.isLocationServiceEnabled();
  } catch (_) {
    // No plugin / no platform: everything reads as undetermined.
  }
  final inputs = PresenceTierInputs(
    pinStored: pin != null,
    locationServicesEnabled: services,
    foregroundPermission: _foreground(permission),
    backgroundPermission: _background(permission),
    geofenceArmed: await MyazaBackgroundPresence.isArmed(),
    foregroundServiceRunning: await MyazaPresenceService.isRunning(),
  );
  return PresenceStatus(
    tier: resolvePresenceTier(inputs),
    pinStored: inputs.pinStored,
    alwaysOn: pin?.alwaysOn == true,
    locationServicesEnabled: inputs.locationServicesEnabled,
    foregroundPermission: inputs.foregroundPermission,
    backgroundPermission: inputs.backgroundPermission,
    geofenceArmed: inputs.geofenceArmed,
    foregroundServiceRunning: inputs.foregroundServiceRunning,
  );
}

/// Where [openLocationSettings] should land: the app's own permissions page,
/// or the phone's location-services screen (the toggle).
enum PresenceSettingsTarget { app, services }

/// Deep-link to Settings, the only road back after a denial or a switched-off
/// toggle. [PresenceSettingsTarget.app] (the default) opens the app's own
/// page; [PresenceSettingsTarget.services] opens the phone's location screen
/// where the toggle lives. Never throws; a host may call it from a button.
Future<void> openLocationSettings({
  PresenceSettingsTarget target = PresenceSettingsTarget.app,
}) async {
  try {
    if (target == PresenceSettingsTarget.services) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  } catch (_) {
    // Nothing to do: the OS refused, and the host's copy already told the
    // person where to go by hand.
  }
}
