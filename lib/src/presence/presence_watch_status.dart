import 'package:dio/dio.dart';

import '../utils/resolve_url.dart';

// Where a user's presence check stands ON THE SERVER, for the host app to
// show. `presenceStatus()` answers for the phone (permissions, pin, tier);
// this answers for the check itself (running, verified, how far along).
//
// The server answers `notStarted` for an unknown user, a business and a user
// with no check alike, on purpose, so `notStarted` never says which. It never
// returns the pin, the address or a coordinate.

/// The server's status words. `unknown` is a word this SDK build does not
/// know yet; treat it as "still in progress".
enum PresenceWatchState {
  notStarted,
  inProgress,
  verified,
  failed,
  inconclusive,
  expired,
  revoked,
  unknown,
}

class PresenceWatchStatus {
  final PresenceWatchState state;

  /// The server's own word for [state], as sent.
  final String rawStatus;
  final DateTime? startedAt;
  final DateTime? deadlineAt;
  final DateTime? decidedAt;

  /// 0..1 of the way to verified, on weighted evidence. Null with no check.
  final double? progress;
  final int? nightsObserved;
  final int? daysObserved;

  /// Which kind of evidence has arrived so far (the server's word), if any.
  final String? tier;
  final bool alwaysOn;
  final DateTime? nextCycleAt;

  /// The organisation stopped monitoring and nothing has started since.
  final bool stopped;

  const PresenceWatchStatus({
    required this.state,
    required this.rawStatus,
    this.startedAt,
    this.deadlineAt,
    this.decidedAt,
    this.progress,
    this.nightsObserved,
    this.daysObserved,
    this.tier,
    this.alwaysOn = false,
    this.nextCycleAt,
    this.stopped = false,
  });
}

const Map<String, PresenceWatchState> _states = {
  'not_started': PresenceWatchState.notStarted,
  'in_progress': PresenceWatchState.inProgress,
  'verified': PresenceWatchState.verified,
  'failed': PresenceWatchState.failed,
  'inconclusive': PresenceWatchState.inconclusive,
  'expired': PresenceWatchState.expired,
  'revoked': PresenceWatchState.revoked,
};

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
int? _int(Object? v) => v is num ? v.toInt() : null;

/// Pure: the response body as a [PresenceWatchStatus], or null when the body
/// carries no status at all.
PresenceWatchStatus? parsePresenceWatchStatus(Map<String, dynamic>? body) {
  final raw = body?['status'];
  if (body == null || raw is! String) return null;
  final progress = body['progress'];
  final p = progress is Map ? progress : null;
  final score = p?['score'];
  return PresenceWatchStatus(
    state: _states[raw] ?? PresenceWatchState.unknown,
    rawStatus: raw,
    startedAt: _date(body['startedAt']),
    deadlineAt: _date(body['deadlineAt']),
    decidedAt: _date(body['decidedAt']),
    progress: score is num ? score.toDouble().clamp(0.0, 1.0) : null,
    nightsObserved: _int(p?['nightsObserved']),
    daysObserved: _int(p?['daysObserved']),
    tier: body['tier'] is String ? body['tier'] as String : null,
    alwaysOn: body['alwaysOn'] == true,
    nextCycleAt: _date(body['nextCycleAt']),
    stopped: body['stopped'] == true || raw == 'revoked',
  );
}

/// Reads the check's status with the publishable key. Never throws: null
/// means the server could not be reached or refused the key.
Future<PresenceWatchStatus?> fetchPresenceWatchStatus({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
}) async {
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
    return parsePresenceWatchStatus(res.data);
  } catch (_) {
    return null;
  }
}
