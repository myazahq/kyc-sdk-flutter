import 'dart:typed_data';

import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/device_attestation.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/device_intel_platform.dart';

// Shared fakes for the device-intel tests: the native half and the challenge
// endpoint, so the Dart side can be pinned without a device.

final challengeBytes = Uint8List.fromList(List.generate(32, (i) => i));

class FakeNative implements DeviceIntelPlatform {
  Map<String, dynamic>? state = {'supported': true, 'keyId': 'key-1'};
  Map<String, dynamic>? attestOut;
  String? token = 'pi-token';
  String? stable = 'stable-1';
  Map<String, dynamic>? integrityOut = {
    'rooted': false,
    'hooked': false,
    'signals': []
  };
  Duration delay = Duration.zero;
  Uint8List? lastHash;
  bool? lastAttest;
  String? lastRequestHash;

  @override
  Future<Map<String, dynamic>?> appAttestState() async => state;

  @override
  Future<Map<String, dynamic>?> appAttest({
    String? keyId,
    required Uint8List clientDataHash,
    required bool attest,
  }) async {
    lastHash = clientDataHash;
    lastAttest = attest;
    await Future<void>.delayed(delay);
    return attestOut ??
        (attest
            ? {'keyId': keyId ?? 'new-key', 'attestation': 'QVRU'}
            : {'keyId': keyId, 'assertion': 'QVNT'});
  }

  @override
  Future<String?> playIntegrityToken({
    required String cloudProjectNumber,
    required String requestHash,
  }) async {
    lastRequestHash = requestHash;
    return token;
  }

  @override
  Future<String?> stableId() async => stable;

  @override
  Future<Map<String, dynamic>?> integrity() async => integrityOut;
}

ChallengeFetcher fetcher(
        {bool attest = false, bool fail = false, List<String?>? keys}) =>
    ({required String platform, String? keyId}) async {
      keys?.add(keyId);
      if (fail) return null;
      return DeviceChallenge(id: 'ch_1', bytes: challengeBytes, attest: attest);
    };
