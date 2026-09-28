import '../config/kyc_config.dart';
import 'background_presence.dart';
import 'presence_reporter.dart';

// ─── What the SDK does ON ITS OWN when a presence flow is submitted ─────────
//
// Until this existed, every observation depended on the host app calling
// MyazaAddressPresence.report() or MyazaBackgroundPresence.enable() itself,
// and companies that wired up the flow and not those calls got watches stuck
// at 0 days / 0 nights until they lapsed (production, 2026-09-28).
//
//   1. Background monitoring, ON unless the workflow sets
//      `presence.background: false`: the SDK asks for the "always" location
//      permission and arms the native geofence, so the phone reports stays
//      with the app closed. The primer told the person this prompt was coming.
//      It needs the host's background-location declarations (manifest and
//      Info.plist); without them it degrades to the foreground tier.
//   2. The first report: the person is standing at the address they just
//      pinned, so the watch gets its first day (and night, when submitted at
//      night) with nothing for the host to do. The reporter waits for the
//      watch the server mints seconds after the submission.
//
// Later days without background monitoring still need the host's reporter on
// app open. Fire-and-forget by contract: never awaited by the flow, never
// throws, and a host that also makes these calls is harmless.
// Mirrors the RN SDK's presence/auto-report.ts — keep the two in lockstep.

/// Whether a submitted flow should make the SDK's own presence calls.
bool shouldAutoReportPresence(MyazaKYCConfig config) {
  if (config.addressCollection?.presenceEnabled != true) return false;
  final userId = config.userId;
  return userId != null && userId.trim().isNotEmpty;
}

/// Background monitoring is on unless the workflow turns it off.
bool wantsBackgroundPresence(MyazaKYCConfig config) =>
    shouldAutoReportPresence(config) && config.addressCollection?.presenceBackground != false;

typedef PresenceReportFn = Future<PresenceReportResult> Function({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
});

typedef BackgroundEnableFn = Future<EnableBackgroundResult> Function({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
});

class AutoReportOutcome {
  final EnableBackgroundResult? background;
  final PresenceReportResult? report;
  const AutoReportOutcome(this.background, this.report);
}

Future<AutoReportOutcome?> autoReportPresence(
  MyazaKYCConfig config, {
  PresenceReportFn report = MyazaAddressPresence.report,
  BackgroundEnableFn enableBackground = MyazaBackgroundPresence.enable,
}) async {
  if (!shouldAutoReportPresence(config)) return null;
  final userId = config.userId!;
  // Background first: its permission prompt belongs on the success screen,
  // not a minute later when the report has finished waiting for the watch.
  EnableBackgroundResult? background;
  if (wantsBackgroundPresence(config)) {
    try {
      background = await enableBackground(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
    } catch (_) {
      background = null;
    }
  }
  PresenceReportResult? reported;
  try {
    reported = await report(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
  } catch (_) {
    reported = null;
  }
  return AutoReportOutcome(background, reported);
}
