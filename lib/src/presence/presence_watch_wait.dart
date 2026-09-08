import 'package:dio/dio.dart';

import '../utils/resolve_url.dart';

// ─── Waiting for the watch ───────────────────────────────────────────────────
//
// The server mints an AddressWatch in the post-terminal hook chain, seconds
// AFTER a submission is accepted, and its ingest is enumeration-safe by
// contract: an observation for a user with no live watch answers
// `accepted: 0` exactly as an unknown user would, and is dropped. So a report
// made the moment the flow submits — the natural place for a host to make one
// — landed on nothing (iPhone + S24, 2026-09-07: three watches in a row lapsed
// INCONCLUSIVE with zero observations while both phones sat at the pin). The
// reporter therefore asks where the watch stands before it posts, and when
// the pin was captured minutes ago it WAITS for the watch to appear, bounded,
// rather than posting into the gap. Mirrors the RN SDK's presence/watch-wait.ts
// — keep the two in lockstep.

/// A pin saved this recently was captured by a flow whose watch may still be
/// minting.
const Duration kFreshPinWindow = Duration(minutes: 15);

/// How long a submit-time report waits for its watch before giving up.
const Duration kWatchWait = Duration(seconds: 90);
const Duration kWatchPoll = Duration(seconds: 3);

enum WatchPresence { live, absent, unknown }

bool pinIsFresh(String savedAt, {DateTime? now}) {
  final saved = DateTime.tryParse(savedAt);
  if (saved == null) return false;
  return (now ?? DateTime.now()).difference(saved) <= kFreshPinWindow;
}

/// The server's public status for the user's watch, or null when it could
/// not be read.
Future<String?> fetchWatchStatus(
  String apiKey,
  String? devUrl,
  String externalUserId,
) async {
  try {
    final dio = Dio(BaseOptions(
      baseUrl: resolveBaseUrl(apiKey, devUrl: devUrl),
      headers: {'Authorization': 'Bearer $apiKey'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    final res = await dio.get<Map<String, dynamic>>(
      '/api/kyc/address/presence/${Uri.encodeComponent(externalUserId)}',
    );
    final status = res.data?['status'];
    return status is String ? status : null;
  } catch (_) {
    return null;
  }
}

typedef WatchStatusReader = Future<String?> Function();

/// Whether a live watch exists to receive a report. Only `in_progress` is
/// live: a resolved cycle, or none at all, drops what is posted. An
/// unreadable status is `unknown`, and the post goes ahead — a network doubt
/// must not silence a report the server might accept. A FRESH pin changes the
/// rule: its watch is probably still being minted (or the previous cycle has
/// just lapsed and the new one is about to replace it), so the status is
/// re-read until it turns live or the wait runs out.
Future<WatchPresence> awaitWatch({
  required bool fresh,
  required WatchStatusReader fetchStatus,
  Future<void> Function(Duration)? sleep,
  DateTime Function()? now,
  Duration waitFor = kWatchWait,
  Duration poll = kWatchPoll,
}) async {
  final doSleep = sleep ?? Future<void>.delayed;
  final clock = now ?? DateTime.now;
  final deadline = clock().add(waitFor);
  while (true) {
    final status = await fetchStatus();
    if (status == 'in_progress') return WatchPresence.live;
    if (!fresh) return status == null ? WatchPresence.unknown : WatchPresence.absent;
    if (!clock().isBefore(deadline)) {
      return status == null ? WatchPresence.unknown : WatchPresence.absent;
    }
    await doSleep(poll);
  }
}
