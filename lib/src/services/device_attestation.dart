import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'api_service.dart' show DeviceChallenge;
import 'device_intel_platform.dart';

// ─── Device attestation: the platform vouches for the app and the device ─────
//
// `fingerprint.attestation` of the device-intel wire contract (kyc-core
// docs/DEVICE_INTEL_WIRE.md §2). Both platforms start with a single-use server
// challenge; the SDK only collects, the server verifies.
//
//   • iOS: App Attest. One key per install, its keyId in the Keychain. The
//     server says whether it wants an attestation (`attest: true`) or an
//     assertion; clientDataHash = SHA-256(challenge bytes).
//   • Android: Play Integrity, Standard API, only when the server names a
//     Google Cloud project. requestHash = lowercase hex SHA-256(challenge).
//
// The whole step is bounded by [kAttestationBudget]; a timeout, an unsupported
// device, a refused challenge or any native error is null, and the submission
// goes out without an attestation. It never blocks one.

/// `POST /api/kyc/device/challenge`, as the SDK's API client exposes it.
typedef ChallengeFetcher = Future<DeviceChallenge?> Function({
  required String platform,
  String? keyId,
});

/// The longest attestation may add to a submission.
const Duration kAttestationBudget = Duration(seconds: 5);

/// The `attestation` block for [platform] (`ios` | `android`), or null.
Future<Map<String, dynamic>?> collectAttestation({
  required String? platform,
  required DeviceIntelPlatform native,
  required ChallengeFetcher fetchChallenge,
  String? cloudProjectNumber,
  Duration budget = kAttestationBudget,
}) async {
  final Future<Map<String, dynamic>?> work = switch (platform) {
    'ios' => _appAttest(native, fetchChallenge),
    'android' => _playIntegrity(native, fetchChallenge, cloudProjectNumber),
    _ => Future.value(null),
  };
  try {
    return await work.timeout(budget, onTimeout: () => null);
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> _appAttest(
  DeviceIntelPlatform native,
  ChallengeFetcher fetchChallenge,
) async {
  final state = await native.appAttestState();
  // Simulators and pre-iOS-14 devices: App Attest is not there to ask.
  if (state == null || state['supported'] != true) return null;
  final stored = _nonEmpty(state['keyId']);

  final challenge = await fetchChallenge(platform: 'ios', keyId: stored);
  if (challenge == null) return null;

  // No key yet means nothing could be asserted: attest whatever the server said.
  final attest = challenge.attest || stored == null;
  final clientDataHash =
      Uint8List.fromList(sha256.convert(challenge.bytes).bytes);
  final out = await native.appAttest(
    keyId: stored,
    clientDataHash: clientDataHash,
    attest: attest,
  );
  final keyId = _nonEmpty(out?['keyId']);
  final attestation = _nonEmpty(out?['attestation']);
  final assertion = _nonEmpty(out?['assertion']);
  if (keyId == null) return null;
  if (attest ? attestation == null : assertion == null) return null;

  return {
    'platform': 'ios',
    'kind': 'app_attest',
    'challengeId': challenge.id,
    'keyId': keyId,
    if (attest) 'attestation': attestation else 'assertion': assertion,
  };
}

Future<Map<String, dynamic>?> _playIntegrity(
  DeviceIntelPlatform native,
  ChallengeFetcher fetchChallenge,
  String? cloudProjectNumber,
) async {
  // No project named by the server: Play Integrity tokens could not be
  // decoded for this org, so none is requested.
  final project = _nonEmpty(cloudProjectNumber);
  if (project == null) return null;

  final challenge = await fetchChallenge(platform: 'android');
  if (challenge == null) return null;

  // Digest.toString() is lowercase hex, exactly what the server rehashes.
  final requestHash = sha256.convert(challenge.bytes).toString();
  final token = _nonEmpty(await native.playIntegrityToken(
    cloudProjectNumber: project,
    requestHash: requestHash,
  ));
  if (token == null) return null;

  return {
    'platform': 'android',
    'kind': 'play_integrity',
    'challengeId': challenge.id,
    'token': token,
  };
}

String? _nonEmpty(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
