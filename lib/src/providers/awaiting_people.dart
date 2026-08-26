import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/api_service.dart';

// The SERVER's list of who a submitted KYB application is waiting on — the
// Flutter port of the RN SDK's useAwaitingPeople and the web SDK's
// use-awaiting-people. Keep all three in lockstep.
//
// MEMBERSHIP settles once: registry discovery runs AFTER submission and can add
// people the applicant never listed, so nothing renders until the server says it
// has finished (`keyPeopleSettled`). A list shown earlier is one director short
// and would be contradicted moments later.
//
// STATUS stays live: the people named go and verify after this screen is first
// shown, so once settled the list re-reads slowly while anybody still owes a
// check — and re-reads on foreground, which is exactly when a stale badge would
// be noticed.

/// How often to re-ask while the server says it is still reconciling.
const Duration _retryInterval = Duration(milliseconds: 1500);

/// How long to wait before showing whatever there is. Discovery's final write is
/// best-effort, and a spinner forever is worse than a list that might be short.
const Duration _giveUp = Duration(seconds: 15);

/// Status-refresh cadence once settled, while anybody owes a check.
const Duration _pollInterval = Duration(seconds: 20);

/// Polls the completed-session summary and exposes the people list.
///
/// [people] is null until the list is worth showing — deliberately distinct
/// from an empty list, which would claim there is nobody to verify.
class AwaitingPeopleController extends ChangeNotifier with WidgetsBindingObserver {
  AwaitingPeopleController({
    required KYCApiService api,
    required this.sessionId,
  }) : _api = api {
    if (sessionId == null) return;
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    unawaited(_read());
  }

  final KYCApiService _api;
  final String? sessionId;

  List<AwaitingPerson>? _people;
  List<AwaitingPerson>? get people => _people;

  DateTime _startedAt = DateTime.now();
  Timer? _timer;
  bool _committed = false;
  bool _disposed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is exactly when a stale badge would be noticed.
    if (state != AppLifecycleState.resumed || _disposed) return;
    _timer?.cancel();
    unawaited(_read());
  }

  Future<void> _read() async {
    if (_disposed || sessionId == null) return;

    SessionSummaryResponse? summary;
    try {
      summary = await _api.sessionSummary(sessionId!);
    } catch (_) {
      summary = null;
    }
    if (_disposed) return;

    final expired = DateTime.now().difference(_startedAt) > _giveUp;

    if (summary != null && (summary.keyPeopleSettled || expired)) {
      _committed = true;
      _people = summary.keyPeople;
      notifyListeners();
      if (summary.keyPeople.any((p) => p.stillOwes)) _schedule(_pollInterval);
      return;
    }
    if (_committed) {
      // One failed refresh must not end the updates: the list on screen is
      // still true, only a little older.
      _schedule(_pollInterval);
      return;
    }
    if (expired) {
      // Nothing readable at all — leave the list ABSENT rather than empty,
      // which would claim there is nobody to verify.
      return;
    }
    _schedule(_retryInterval);
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(_read()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (sessionId != null) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
