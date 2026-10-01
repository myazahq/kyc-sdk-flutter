import 'dart:io' show Platform;

import 'device_attestation.dart';
import 'device_intel_platform.dart';

// ─── Mobile fingerprint additions ────────────────────────────────────────────
//
// `stableId`, `integrity` and `attestation` of the device-intel wire contract
// (kyc-core docs/DEVICE_INTEL_WIRE.md §2). They ride BESIDE `components`, never
// inside it: the server hashes `components`, and a new key there would move
// every device's hash.
//
// Collected only while Device Intelligence is on (fingerprint_payload.dart),
// and only ever as a soft signal: whatever cannot be read is omitted. The
// stable id and the integrity heuristics are read once per process; the
// attestation is fresh per submission (its challenge is single-use).

/// Every token the integrity heuristics may report. Add-only, and a token
/// outside this set is dropped rather than sent.
const Set<String> kRootSignals = {
  'su_binary',
  'magisk',
  'test_keys',
  'busybox',
  'root_apps',
  'writable_system',
  'jailbreak_paths',
  'cydia_scheme',
  'sandbox_escape',
};
const Set<String> kHookSignals = {'dyld_injection', 'frida', 'debugger'};

/// The longest the stable id or the integrity heuristics may take each.
/// They run alongside the attestation, so the total stays inside its budget.
const Duration kNativeSignalBudget = Duration(milliseconds: 1500);

const int kStableIdMax = 128;

class DeviceSignals {
  DeviceSignals({DeviceIntelPlatform? native, String? platform})
      : _native = native ?? const MethodChannelDeviceIntel(),
        _platform = platform ?? _currentPlatform();

  static final DeviceSignals instance = DeviceSignals();

  final DeviceIntelPlatform _native;
  final String? _platform;

  String? _stableId;
  Map<String, dynamic>? _integrity;

  /// `{ stableId?, integrity?, attestation? }`. Never throws; an empty map on
  /// a platform that has none of them.
  Future<Map<String, dynamic>> collect({
    required ChallengeFetcher fetchChallenge,
    String? cloudProjectNumber,
  }) async {
    if (_platform != 'ios' && _platform != 'android') return const {};
    final results = await Future.wait<Object?>([
      _readStableId(),
      _readIntegrity(),
      collectAttestation(
        platform: _platform,
        native: _native,
        fetchChallenge: fetchChallenge,
        cloudProjectNumber: cloudProjectNumber,
      ),
    ]);
    final stableId = results[0] as String?;
    final integrity = results[1] as Map<String, dynamic>?;
    final attestation = results[2] as Map<String, dynamic>?;
    return {
      if (stableId != null) 'stableId': stableId,
      if (integrity != null) 'integrity': integrity,
      if (attestation != null) 'attestation': attestation,
    };
  }

  Future<String?> _readStableId() async {
    if (_stableId != null) return _stableId;
    final raw = await _bounded(_native.stableId());
    final id = raw?.trim();
    if (id == null || id.isEmpty || id.length > kStableIdMax) return null;
    return _stableId = id;
  }

  Future<Map<String, dynamic>?> _readIntegrity() async {
    if (_integrity != null) return _integrity;
    final normalised = normaliseIntegrity(await _bounded(_native.integrity()));
    // A failed read is retried next time; a completed one is kept.
    if (normalised != null) _integrity = normalised;
    return normalised;
  }

  static Future<T?> _bounded<T>(Future<T?> work) async {
    try {
      return await work.timeout(kNativeSignalBudget, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static String? _currentPlatform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {/* no dart:io platform */}
    return null;
  }
}

/// The wire shape of the native heuristics' answer, or null when there is
/// none. `rooted` / `hooked` stay null when the native side could not run
/// them; `signals` keeps only known tokens, each once.
Map<String, dynamic>? normaliseIntegrity(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final rawSignals = raw['signals'];
  final signals = <String>[
    if (rawSignals is List)
      for (final s in rawSignals.whereType<String>().toSet())
        if (kRootSignals.contains(s) || kHookSignals.contains(s)) s,
  ];
  final rooted = raw['rooted'];
  final hooked = raw['hooked'];
  return {
    'rooted': rooted is bool ? rooted : null,
    'hooked': hooked is bool ? hooked : null,
    'signals': signals,
  };
}
