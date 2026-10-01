import 'fingerprint_service.dart';

// ─── The Device Intelligence gate, in one place ──────────────────────────────
//
// Everything the device-intel wire contract adds (kyc-core
// docs/DEVICE_INTEL_WIRE.md) is collected ONLY while the workflow's
// `deviceIntelligence` is on: the fingerprint and its mobile additions on the
// submission, and the per-install id on every upload. Both decisions live
// here so they cannot drift apart, and so they can be tested without a flow.

/// Additions that may join the fingerprint. Anything else an extras source
/// returns is dropped: `deviceId` and `components` belong to the base alone.
const List<String> kFingerprintExtraKeys = [
  'stableId',
  'integrity',
  'attestation'
];

/// `metadata.device.fingerprint`, or null when Device Intelligence is off.
///
/// [base] is `{ deviceId?, components }`; [extras] the mobile additions. A
/// failed base omits the fingerprint; failed extras leave the base as it was.
Future<Map<String, dynamic>?> collectFingerprint({
  required bool deviceIntelligence,
  required Future<Map<String, dynamic>> Function() base,
  required Future<Map<String, dynamic>> Function() extras,
}) async {
  if (!deviceIntelligence) return null;
  final Map<String, dynamic> fingerprint;
  try {
    fingerprint = await base();
  } catch (_) {
    return null;
  }
  Map<String, dynamic> more;
  try {
    more = await extras();
  } catch (_) {
    more = const {};
  }
  // A new map: the base is cached by FingerprintService and must not grow a
  // single-use attestation that a later submission would replay.
  return {
    ...fingerprint,
    for (final key in kFingerprintExtraKeys)
      if (more[key] != null) key: more[key],
  };
}

/// What the API client reads the upload header from: the same per-install id
/// the fingerprint carries, or nothing at all while Device Intelligence is off.
Future<String?> Function()? uploadDeviceIdSource({
  required bool deviceIntelligence,
  Future<String?> Function()? read,
}) =>
    deviceIntelligence
        ? (read ?? FingerprintService.instance.persistentDeviceId)
        : null;
