import 'package:geolocator/geolocator.dart';

import 'background_presence.dart';
import 'presence_store.dart';
import 'presence_watch_wait.dart';

// ─── The reporter switches background monitoring on for a running check ──────
//
// The SDK arms the background tier once, right after a verification is
// submitted (presence_auto_report.dart). Someone verified before the SDK
// could ask for "allow all the time", or on an always-on arrangement whose
// renewals never run the flow again, never passes that moment: their check
// collected app-open reports only. The one SDK call their app already makes is
// the reporter, so the reporter arms it.
//
// The rule ([shouldArmBackground]) is pure. It mirrors the RN SDK's
// presence/auto-arm.ts; change both together.

/// `ask` shows the OS prompt (once), `silent` arms with none, `skip` does nothing.
enum ArmDecision { ask, silent, skip }

ArmDecision shouldArmBackground({
  /// The host passed `autoBackground: false`.
  required bool optedOut,

  /// The pin was saved moments ago: the flow's own submit step arms it.
  required bool fresh,
  required StoredPin pin,

  /// The server's word on the check, or null when it could not be read.
  required WatchState? watch,

  /// The fence is already registered with the OS.
  required bool armed,

  /// "Allow all the time" is already granted, so arming shows no prompt.
  required bool alwaysGranted,
}) {
  if (optedOut || fresh || armed) return ArmDecision.skip;
  // The workflow switched background monitoring off for this check.
  if (!pin.background) return ArmDecision.skip;
  // Unknown is never "running": without the server's word nobody is asked.
  if (watch == null || watch.stopped) return ArmDecision.skip;
  // A check in flight, or an always-on arrangement between two checks (only a
  // verified or inconclusive check is followed by another).
  final renews = watch.status == 'verified' || watch.status == 'inconclusive';
  final live = watch.status == 'in_progress' || (pin.alwaysOn && renews);
  if (!live) return ArmDecision.skip;
  if (alwaysGranted) return ArmDecision.silent;
  // One ask per stored address, whatever the answer was.
  return pin.backgroundAsked ? ArmDecision.skip : ArmDecision.ask;
}

/// Arms the background tier when the rule says so. Never throws.
Future<EnableBackgroundResult?> maybeArmBackground({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
  required bool autoBackground,
  required StoredPin pin,
  required WatchState? watch,
  required bool fresh,
}) async {
  try {
    // Decided before anything is read from the OS when the answer is already no.
    if (!autoBackground || fresh || !pin.background) return null;
    final armed = await MyazaBackgroundPresence.isArmed();
    final permission = await Geolocator.checkPermission();
    final decision = shouldArmBackground(
      optedOut: !autoBackground,
      fresh: fresh,
      pin: pin,
      watch: watch,
      armed: armed,
      alwaysGranted: permission == LocationPermission.always,
    );
    if (decision == ArmDecision.skip) return null;
    // Marked BEFORE the prompt: an app closed while it is showing has asked.
    if (decision == ArmDecision.ask) await markBackgroundAsked(externalUserId);
    return await MyazaBackgroundPresence.enable(
      apiKey: apiKey,
      externalUserId: externalUserId,
      devUrl: devUrl,
    );
  } catch (_) {
    return null;
  }
}
