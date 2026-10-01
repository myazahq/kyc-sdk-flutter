import 'package:flutter/services.dart';

// ─── Device Intelligence: the native half ────────────────────────────────────
//
// One channel, `kyc_sdk_flutter/device_intel`, answered by
// DeviceIntelChannel.swift (iOS) and DeviceIntelHandler.kt (Android). It serves
// the mobile-only fingerprint additions of the device-intel wire contract
// (kyc-core docs/DEVICE_INTEL_WIRE.md):
//
//   • stableId: an id that survives a reinstall (Keychain UUID / ANDROID_ID).
//   • integrity: root / jailbreak / hook heuristics. Never prompts.
//   • App Attest (iOS) and Play Integrity (Android) for `attestation`.
//
// Every call is best-effort: a missing plugin (tests, an unsupported platform),
// a native error or a malformed answer is null, never a throw.

abstract class DeviceIntelPlatform {
  /// The reinstall-surviving id, or null.
  Future<String?> stableId();

  /// `{ rooted, hooked, signals }` straight from the heuristics, or null.
  Future<Map<String, dynamic>?> integrity();

  /// iOS: `{ supported, keyId? }`, the stored App Attest key. Null elsewhere.
  Future<Map<String, dynamic>?> appAttestState();

  /// iOS: `{ keyId, attestation }` when [attest], else `{ keyId, assertion }`
  /// (both base64). Null when App Attest cannot answer.
  Future<Map<String, dynamic>?> appAttest({
    String? keyId,
    required Uint8List clientDataHash,
    required bool attest,
  });

  /// Android: a Play Integrity (Standard API) token, or null.
  Future<String?> playIntegrityToken({
    required String cloudProjectNumber,
    required String requestHash,
  });
}

class MethodChannelDeviceIntel implements DeviceIntelPlatform {
  const MethodChannelDeviceIntel();

  static const MethodChannel _channel =
      MethodChannel('kyc_sdk_flutter/device_intel');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, args);
      return raw is T ? raw : null;
    } catch (_) {
      return null; // MissingPluginException, PlatformException, anything
    }
  }

  Future<Map<String, dynamic>?> _map(String method, [Object? args]) async =>
      (await _call<Map<Object?, Object?>>(method, args))
          ?.cast<String, dynamic>();

  @override
  Future<String?> stableId() => _call<String>('stableId');

  @override
  Future<Map<String, dynamic>?> integrity() => _map('integrity');

  @override
  Future<Map<String, dynamic>?> appAttestState() => _map('appAttestState');

  @override
  Future<Map<String, dynamic>?> appAttest({
    String? keyId,
    required Uint8List clientDataHash,
    required bool attest,
  }) =>
      _map('appAttest', {
        'keyId': keyId,
        'clientDataHash': clientDataHash,
        'attest': attest,
      });

  @override
  Future<String?> playIntegrityToken({
    required String cloudProjectNumber,
    required String requestHash,
  }) =>
      _call<String>('playIntegrityToken', {
        'cloudProjectNumber': cloudProjectNumber,
        'requestHash': requestHash,
      });
}
