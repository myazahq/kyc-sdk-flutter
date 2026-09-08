part of 'api_service.dart';

// ─── Biometric re-authentication calls ───────────────────────────────────────
//
// A `part` so the calls reach the library-private Dio client and error mapper
// (the address calls' idiom). Mirrors the web and RN SDKs' shapes — keep the
// three in lockstep. Publishable-safe: a verdict, a confidence and a
// single-use proof token. No PII.

/// `POST /api/kyc/biometric/authenticate`. `token` is present only on
/// `authenticated`; redeem it from your backend with a secret key at
/// `/biometric/verify-proof`.
class BiometricAuthResponse {
  final bool authenticated;

  /// `authenticated` | `no_match` | `liveness_failed`.
  final String status;
  final double? confidence;
  final bool live;
  final String attemptId;
  final String? token;

  const BiometricAuthResponse({
    required this.authenticated,
    required this.status,
    required this.confidence,
    required this.live,
    required this.attemptId,
    this.token,
  });

  factory BiometricAuthResponse.fromJson(Map<String, dynamic> json) =>
      BiometricAuthResponse(
        authenticated: json['authenticated'] == true,
        status: json['status']?.toString() ?? 'no_match',
        confidence: (json['confidence'] as num?)?.toDouble(),
        live: json['live'] == true,
        attemptId: json['attemptId']?.toString() ?? '',
        token: json['token']?.toString(),
      );
}

/// `GET /api/kyc/biometric/status/:externalUserId` — whether to OFFER re-auth.
class BiometricStatusResponse {
  final bool enrolled;
  final String? enrolledAt;
  final String? lastAuthenticatedAt;

  const BiometricStatusResponse({
    required this.enrolled,
    this.enrolledAt,
    this.lastAuthenticatedAt,
  });

  factory BiometricStatusResponse.fromJson(Map<String, dynamic> json) =>
      BiometricStatusResponse(
        enrolled: json['enrolled'] == true,
        enrolledAt: json['enrolledAt']?.toString(),
        lastAuthenticatedAt: json['lastAuthenticatedAt']?.toString(),
      );
}

extension KYCApiBiometric on KYCApiService {
  /// Re-authenticate a verified user by matching a live selfie 1:1 against
  /// their KYC enrollment reference. Uniform 404 `not_enrolled` — a missing
  /// entity, a business entity and no template all answer the same, so
  /// nothing can be probed.
  Future<BiometricAuthResponse> authenticate({
    required String externalUserId,
    required String selfieMediaId,
    required String livenessMode,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/biometric/authenticate',
        data: {
          'externalUserId': externalUserId,
          'selfie': selfieMediaId,
          'liveness': {'mode': livenessMode, 'passed': true},
        },
      );
      return BiometricAuthResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'biometric_failed');
    }
  }

  /// Whether a user is enrolled for face re-auth (whether to OFFER it).
  Future<BiometricStatusResponse> biometricStatus(String externalUserId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/biometric/status/${Uri.encodeComponent(externalUserId)}',
      );
      return BiometricStatusResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'biometric_failed');
    }
  }
}
