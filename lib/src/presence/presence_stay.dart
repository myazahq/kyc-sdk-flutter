import 'package:flutter/services.dart';

// The open stay, for the host app to show. The background tier sends nothing
// while a stay is merely running: it reports when the person leaves, or at a
// "still here" check-in (35 minutes after they arrive, then every three
// hours; PresenceFold on each platform). Between those moments the server
// has nothing new, so "0 days" on a dashboard can mean "inside since 18:04,
// first report due 18:39" rather than "broken". This is how a host says so.
//
// Read from the phone only. Nothing here leaves the device.

class PresenceStay {
  /// When the phone last arrived inside the fence.
  final DateTime since;

  /// The earliest moment a check-in can record this stay. The OS decides when
  /// a background check-in actually runs, so this is "not before", never a
  /// promise; opening the app after it records at once.
  final DateTime nextReportAt;

  const PresenceStay({required this.since, required this.nextReportAt});
}

DateTime? _at(Object? v) =>
    v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// Pure: the native answer as a [PresenceStay]; null with no stay open, or
/// when the plugin is an older build that does not answer.
PresenceStay? parsePresenceStay(Map<Object?, Object?>? raw) {
  final since = _at(raw?['since']);
  final next = _at(raw?['nextReportAt']);
  if (since == null || next == null) return null;
  return PresenceStay(since: since, nextReportAt: next);
}

const _channel = MethodChannel('kyc_sdk_flutter/presence');

/// The stay the background tier has open on this phone, or null. Never throws.
Future<PresenceStay?> presenceStay() async {
  try {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('presenceStay');
    return parsePresenceStay(raw);
  } catch (_) {
    return null;
  }
}
