part of 'api_service.dart';

// ─── Device Intelligence calls ───────────────────────────────────────────────
//
// The attestation challenge (kyc-core docs/DEVICE_INTEL_WIRE.md §2) and the
// one config fact it needs. A `part` so it reaches the library-private Dio
// client, like the address calls.

/// Header every `/api/kyc/upload` carries: the same per-install id the
/// submission's `fingerprint.deviceId` carries, so the server can tell whether
/// one session's captures came from more than one device.
const String kDeviceIdHeader = 'X-Myaza-Device-Id';

/// The server caps the header at 64 characters; a longer id is omitted.
const int kDeviceIdHeaderMax = 64;

/// A single-use attestation challenge.
class DeviceChallenge {
  final String id;

  /// The raw challenge bytes (base64 on the wire, 32 bytes).
  final Uint8List bytes;

  /// iOS only: true when the server wants a fresh App Attest attestation
  /// (no key yet, or a key it does not know) rather than an assertion.
  final bool attest;

  const DeviceChallenge(
      {required this.id, required this.bytes, this.attest = false});

  /// Null for anything that is not a usable challenge.
  static DeviceChallenge? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['challengeId'];
    final raw = json['challenge'];
    if (id is! String || id.isEmpty || raw is! String) return null;
    try {
      final bytes = base64.decode(raw);
      if (bytes.isEmpty) return null;
      return DeviceChallenge(
          id: id, bytes: bytes, attest: json['attest'] == true);
    } on FormatException {
      return null;
    }
  }
}

/// `deviceAttestation.playIntegrityCloudProjectNumber`, served by `/config`,
/// the workflow resolution and the hosted bootstrap. Null when absent, which
/// means Play Integrity is skipped.
String? playIntegrityProjectOf(Map<String, dynamic> json) {
  final block = json['deviceAttestation'];
  if (block is! Map) return null;
  final raw = block['playIntegrityCloudProjectNumber'];
  final value = raw is num ? raw.toInt().toString() : raw;
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

extension KYCApiDevice on KYCApiService {
  /// `POST /api/kyc/device/challenge`. Any error (404 when the platform has
  /// attestation off, 503, network) is null: "skip attestation this time".
  Future<DeviceChallenge?> deviceChallenge({
    required String platform,
    String? keyId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/device/challenge',
        data: {
          'platform': platform,
          if (keyId != null && keyId.isNotEmpty) 'keyId': keyId,
        },
      );
      return DeviceChallenge.fromJson(response.data);
    } catch (_) {
      return null;
    }
  }
}
