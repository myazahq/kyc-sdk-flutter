import 'background_presence.dart';
import 'foreground_presence.dart';
import 'presence_store.dart';

// ─── Standing down ───────────────────────────────────────────────────────────
//
// The organisation (or Myaza) can stop a customer's presence monitoring, and
// until now nothing told the phone: the geofence stayed armed, the Android
// foreground service kept its notification up, and the stored pin stayed on
// the device, all reporting to a watch that no longer existed. When the status
// read says monitoring was stopped, the SDK switches off its own side and
// forgets the pin. Never throws. Mirrors the RN SDK's presence/stand-down.ts.
//
// The native side holds ONE armed pin per device, so both tiers are switched
// off whoever they were armed for. A device shared by two monitored users is
// the one case where the second user must enable again.

Future<void> standDownPresence(String externalUserId) async {
  await MyazaBackgroundPresence.disable();
  await MyazaPresenceService.disable();
  try {
    await clearPresencePin(externalUserId);
  } catch (_) {
    // Best-effort by contract.
  }
}
