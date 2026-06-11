import 'dart:typed_data';

import 'package:dio/dio.dart';

// ─── SDK version ─────────────────────────────────────────────────────────────
//
// Sent on every request as the X-SDK-Version header so the server can log
// which SDK versions are in the wild and gate breaking API changes by version.
// Keep in sync with pubspec.yaml `version`.

const String kSdkVersion = '2.0.0';

// ─── Exception ────────────────────────────────────────────────────────────────

class KYCApiException implements Exception {
  final int statusCode;
  final String error;
  final String? message;
  final Map<String, dynamic>? details;

  const KYCApiException({
    required this.statusCode,
    required this.error,
    this.message,
    this.details,
  });

  @override
  String toString() =>
      'KYCApiException($statusCode): $error${message != null ? ' — $message' : ''}';
}

// ─── Upload ───────────────────────────────────────────────────────────────────

/// Allowed media types for the /api/kyc/upload endpoint.
/// Matches the server's `TypeSchema` in routes/sdk/upload.ts.
class MediaType {
  static const documentFront = 'document_front';
  static const documentBack = 'document_back';
  static const selfie = 'selfie';
  static const documentFrontVideo = 'document_front_video';
  static const documentBackVideo = 'document_back_video';
  static const livenessVideo = 'liveness_video';
}

/// Response from `POST /api/kyc/upload` — the stored mediaId referenced later
/// in the verify request.
class UploadResponse {
  final String mediaId;

  const UploadResponse({required this.mediaId});

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      UploadResponse(mediaId: json['mediaId'] as String);
}

// ─── Verify ───────────────────────────────────────────────────────────────────

class VerifyUserData {
  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;

  const VerifyUserData({this.firstName, this.lastName, this.dateOfBirth});

  Map<String, dynamic> toJson() => {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      };
}

class VerifyMediaIds {
  final String? documentFront;
  final String? documentBack;
  final String? selfie;
  final String? documentFrontVideo;
  final String? documentBackVideo;
  final String? livenessVideo;

  const VerifyMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
  });

  Map<String, dynamic> toJson() => {
        if (documentFront != null) 'documentFront': documentFront,
        if (documentBack != null) 'documentBack': documentBack,
        if (selfie != null) 'selfie': selfie,
        if (documentFrontVideo != null) 'documentFrontVideo': documentFrontVideo,
        if (documentBackVideo != null) 'documentBackVideo': documentBackVideo,
        if (livenessVideo != null) 'livenessVideo': livenessVideo,
      };

  bool get isEmpty =>
      documentFront == null &&
      documentBack == null &&
      selfie == null &&
      documentFrontVideo == null &&
      documentBackVideo == null &&
      livenessVideo == null;
}

class VerifyMetadata {
  final String requestId;
  final String? userId;
  final Map<String, String>? extra;
  final Map<String, dynamic>? device;

  const VerifyMetadata({
    required this.requestId,
    this.userId,
    this.extra,
    this.device,
  });

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        if (userId != null) 'userId': userId,
        ...?extra,
        if (device != null) 'device': device,
      };
}

class VerifyRequest {
  final String country;
  final String idType;
  final String? idNumber;
  final VerifyUserData? userData;
  final VerifyMediaIds? mediaIds;
  final VerifyMetadata metadata;

  const VerifyRequest({
    required this.country,
    required this.idType,
    this.idNumber,
    this.userData,
    this.mediaIds,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'idType': idType,
        if (idNumber != null) 'idNumber': idNumber,
        if (userData != null) 'userData': userData!.toJson(),
        if (mediaIds != null && !mediaIds!.isEmpty) 'mediaIds': mediaIds!.toJson(),
        'metadata': metadata.toJson(),
      };
}

class VerifyResponse {
  final String verificationId;
  final String status; // Always 'pending' immediately after submission

  const VerifyResponse({required this.verificationId, required this.status});

  factory VerifyResponse.fromJson(Map<String, dynamic> json) => VerifyResponse(
        verificationId: json['verificationId'] as String,
        status: json['status'] as String,
      );
}

// ─── Status ──────────────────────────────────────────────────────────────────

class StatusUserData {
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final String? dateOfBirth;
  final String? gender;

  const StatusUserData({
    this.firstName,
    this.lastName,
    this.middleName,
    this.dateOfBirth,
    this.gender,
  });

  factory StatusUserData.fromJson(Map<String, dynamic> json) => StatusUserData(
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        middleName: json['middleName'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        gender: json['gender'] as String?,
      );
}

class StatusFacialMatch {
  final bool match;
  final double? confidence;

  const StatusFacialMatch({required this.match, this.confidence});

  factory StatusFacialMatch.fromJson(Map<String, dynamic> json) =>
      StatusFacialMatch(
        match: json['match'] as bool,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

class StatusResult {
  final String? idNumberMasked;
  final StatusUserData? userData;
  final StatusFacialMatch? facialMatch;

  const StatusResult({this.idNumberMasked, this.userData, this.facialMatch});

  factory StatusResult.fromJson(Map<String, dynamic> json) => StatusResult(
        idNumberMasked: json['idNumberMasked'] as String?,
        userData: json['userData'] != null
            ? StatusUserData.fromJson(json['userData'] as Map<String, dynamic>)
            : null,
        facialMatch: json['facialMatch'] != null
            ? StatusFacialMatch.fromJson(
                json['facialMatch'] as Map<String, dynamic>)
            : null,
      );
}

class StatusResponse {
  final String verificationId;
  /// 'pending' | 'verified' | 'failed' | 'not_found' | 'error'
  final String status;
  final String? reason;
  final StatusResult? result;
  final DateTime createdAt;
  final DateTime? completedAt;

  const StatusResponse({
    required this.verificationId,
    required this.status,
    this.reason,
    this.result,
    required this.createdAt,
    this.completedAt,
  });

  bool get isPending => status == 'pending';
  bool get isComplete => !isPending;

  factory StatusResponse.fromJson(Map<String, dynamic> json) => StatusResponse(
        verificationId: json['verificationId'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String?,
        result: json['result'] != null
            ? StatusResult.fromJson(json['result'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );
}

// ─── Config (ID-type access + per-ID feature flags) ─────────────────────────

/// Per-ID feature toggles returned by /api/kyc/config. Mirrors the server's
/// `resolveFeatureAccess` output after global kill-switch + per-ID override
/// + org-wide default precedence.
class SdkIdTypeFeatures {
  final bool documentVerification;
  final bool livenessCheck;
  final bool govDbCheck;

  const SdkIdTypeFeatures({
    required this.documentVerification,
    required this.livenessCheck,
    required this.govDbCheck,
  });

  factory SdkIdTypeFeatures.fromJson(Map<String, dynamic> json) =>
      SdkIdTypeFeatures(
        documentVerification: json['documentVerification'] as bool? ?? true,
        livenessCheck: json['livenessCheck'] as bool? ?? true,
        govDbCheck: json['govDbCheck'] as bool? ?? true,
      );
}

class SdkConfigIdType {
  final String country;
  final String idType;
  final SdkIdTypeFeatures features;

  const SdkConfigIdType({
    required this.country,
    required this.idType,
    required this.features,
  });

  factory SdkConfigIdType.fromJson(Map<String, dynamic> json) =>
      SdkConfigIdType(
        country: json['country'] as String,
        idType: json['idType'] as String,
        features: SdkIdTypeFeatures.fromJson(
          (json['features'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}

/// Org branding returned by /api/kyc/config. Surfaced so the SDK can render the
/// org's own logo when the consumer sets `appearance.logo = 'default'`. `logo`
/// is an absolute, public URL (or null when the org has none configured).
class SdkConfigBranding {
  final String? logo;
  final String? companyName;
  final String? primaryColor;

  const SdkConfigBranding({this.logo, this.companyName, this.primaryColor});

  factory SdkConfigBranding.fromJson(Map<String, dynamic> json) =>
      SdkConfigBranding(
        logo: json['logo'] as String?,
        companyName: json['companyName'] as String?,
        primaryColor: json['primaryColor'] as String?,
      );
}

class SdkConfigResponse {
  /// Server environment derived from the API key — 'SANDBOX' or 'PRODUCTION'.
  final String environment;
  final List<SdkConfigIdType> idTypes;

  /// Org branding (logo, name, color). May be null on older servers.
  final SdkConfigBranding? branding;

  const SdkConfigResponse({
    required this.environment,
    required this.idTypes,
    this.branding,
  });

  factory SdkConfigResponse.fromJson(Map<String, dynamic> json) =>
      SdkConfigResponse(
        environment: json['environment'] as String? ?? 'SANDBOX',
        idTypes: ((json['idTypes'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SdkConfigIdType.fromJson)
            .toList(growable: false),
        branding: json['branding'] != null
            ? SdkConfigBranding.fromJson(
                (json['branding'] as Map).cast<String, dynamic>())
            : null,
      );
}

// ─── Health ───────────────────────────────────────────────────────────────────

class HealthResponse {
  final String status;
  const HealthResponse({required this.status});

  bool get isOk => status == 'ok';

  factory HealthResponse.fromJson(Map<String, dynamic> json) =>
      HealthResponse(status: json['status'] as String);
}

// ─── API service ─────────────────────────────────────────────────────────────

class KYCApiService {
  final Dio _dio;

  /// Resolved base URL the SDK talks to (see `resolveBaseUrl`).
  final String baseUrl;
  final String apiKey;

  KYCApiService({required this.baseUrl, required this.apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'X-SDK-Version': kSdkVersion,
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ── Upload — store a media file during capture ────────────────────────────
  //
  // Single multipart/form-data request to POST /api/kyc/upload. The bytes go to
  // our server, which stores them in R2 and returns { mediaId } — referenced
  // later in the verify request.
  // [type] must be one of MediaType.* (document_front | document_back | selfie | *_video).

  Future<String> upload(
    Uint8List bytes,
    String mimeType,
    String type,
  ) async {
    try {
      final ext = switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'video/webm' => 'webm',
        'video/mp4' => 'mp4',
        _ => 'bin',
      };
      final form = FormData.fromMap({
        'type': type,
        'file': MultipartFile.fromBytes(
          bytes,
          filename: '$type.$ext',
          contentType: DioMediaType.parse(mimeType),
        ),
      });

      final res = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/upload',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          // Multipart uploads can take longer than the default 30s.
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      return UploadResponse.fromJson(res.data!).mediaId;
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'upload_failed');
    }
  }

  // ── Verify — submit verification (async) ───────────────────────────────────
  //
  // Server returns 202 with { verificationId, status: 'pending' } in ~200ms.
  // OCR, YouVerify, and facial comparison happen asynchronously on the server.
  // The result is delivered via webhook or polled via [status].

  Future<VerifyResponse> verify(VerifyRequest request) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/verify',
        data: request.toJson(),
        options: Options(contentType: 'application/json'),
      );
      return VerifyResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Status — poll a verification's current status ──────────────────────────

  Future<StatusResponse> status(String verificationId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/status/$verificationId',
      );
      return StatusResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Config — get the org's allowed IDs + per-ID feature flags ────────────
  //
  // Auth: API key (Bearer pk_*). The SDK calls this once on mount and uses
  // the response to filter the IdType picker and decide whether to skip
  // disabled steps (liveness, etc.).

  Future<SdkConfigResponse> config() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/kyc/config');
      return SdkConfigResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Health check ───────────────────────────────────────────────────────────

  Future<HealthResponse> healthCheck() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/kyc/health');
      return HealthResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  KYCApiException _mapDioError(DioException e, {String? fallbackError}) {
    final statusCode = e.response?.statusCode ?? 0;
    final data = e.response?.data;
    String error = fallbackError ?? 'network_error';
    String? message;
    Map<String, dynamic>? details;

    if (data is Map<String, dynamic>) {
      error = data['error'] as String? ?? error;
      message = data['message'] as String?;
      // 402 insufficient_credits returns { required, balance, currency } at the top level
      if (statusCode == 402) {
        error = 'insufficient_credits';
        details = {
          if (data['required'] != null) 'required': data['required'],
          if (data['balance'] != null) 'balance': data['balance'],
          if (data['currency'] != null) 'currency': data['currency'],
        };
      }
      // 403 feature_disabled carries `feature` (document_verification | gov_db_check).
      // 403 id_type_not_allowed carries `country`, `idType`, `reason`.
      if (statusCode == 403) {
        details = {
          if (data['feature'] != null) 'feature': data['feature'],
          if (data['country'] != null) 'country': data['country'],
          if (data['idType'] != null) 'idType': data['idType'],
          if (data['reason'] != null) 'reason': data['reason'],
        };
        if (details.isEmpty) details = null;
      }
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      error = 'timeout';
      message = 'The request timed out. Please check your connection.';
    } else if (e.type == DioExceptionType.connectionError) {
      error = 'network_error';
      message = 'Unable to connect to the server.';
    }

    if (statusCode == 401) {
      error = 'invalid_api_key';
      message ??= 'Invalid or revoked API key.';
    }

    return KYCApiException(
      statusCode: statusCode,
      error: error,
      message: message,
      details: details,
    );
  }
}
