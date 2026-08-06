import 'dart:typed_data';

import 'package:dio/dio.dart';

// ─── SDK version ─────────────────────────────────────────────────────────────
//
// Sent on every request as the X-SDK-Version header so the server can log
// which SDK versions are in the wild and gate breaking API changes by version.
// Keep in sync with pubspec.yaml `version`.

const String kSdkVersion = '2.1.0';

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
  static const proofOfAddress = 'proof_of_address';
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
  final String? proofOfAddress;

  const VerifyMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
    this.proofOfAddress,
  });

  Map<String, dynamic> toJson() => {
        if (documentFront != null) 'documentFront': documentFront,
        if (documentBack != null) 'documentBack': documentBack,
        if (selfie != null) 'selfie': selfie,
        if (documentFrontVideo != null) 'documentFrontVideo': documentFrontVideo,
        if (documentBackVideo != null) 'documentBackVideo': documentBackVideo,
        if (livenessVideo != null) 'livenessVideo': livenessVideo,
        if (proofOfAddress != null) 'proofOfAddress': proofOfAddress,
      };

  bool get isEmpty =>
      documentFront == null &&
      documentBack == null &&
      selfie == null &&
      documentFrontVideo == null &&
      documentBackVideo == null &&
      livenessVideo == null &&
      proofOfAddress == null;
}

/// Business (KYB) submission block — the registry lookup inputs. Sent instead of
/// media; the server derives the subject type from the (required) published KYB
/// workflow, not this block.
class VerifyBusiness {
  final String registrationNumber;
  final String? registrationName;
  final String? product;

  const VerifyBusiness({
    required this.registrationNumber,
    this.registrationName,
    this.product,
  });

  Map<String, dynamic> toJson() => {
        'registrationNumber': registrationNumber,
        if (registrationName != null && registrationName!.isNotEmpty)
          'registrationName': registrationName,
        if (product != null) 'product': product,
      };
}

/// eMRTD chip payload (base64 DG1 + optional EF.SOD + client-reported session
/// type). Rides the `mediaIds` row json server-side; passive authentication is
/// server-side (the `chipAuth` flag is informational only).
class VerifyNfc {
  final String dg1;
  final String? sod;

  /// Base64 DG2 (the chip portrait). Authenticated server-side against the SOD's
  /// DG2 hash; omitted when the portrait couldn't be read.
  final String? dg2;

  /// STRICTLY `bac` | `pace` | `none` — the server validates it as an enum and
  /// rejects the whole submission for anything else.
  final String chipAuth;

  /// Why the session used [chipAuth]. Diagnostic only; free text.
  final String? paceOutcome;
  final String? paceDetail;

  const VerifyNfc({
    required this.dg1,
    this.sod,
    this.dg2,
    this.chipAuth = 'bac',
    this.paceOutcome,
    this.paceDetail,
  });

  Map<String, dynamic> toJson() => {
        'dg1': dg1,
        if (sod != null) 'sod': sod,
        if (dg2 != null) 'dg2': dg2,
        'chipAuth': chipAuth,
        if (paceOutcome != null) 'paceOutcome': paceOutcome,
        if (paceDetail != null) 'paceDetail': paceDetail,
      };
}

class VerifyMetadata {
  final String requestId;
  final Map<String, String>? extra;
  final Map<String, dynamic>? device;

  const VerifyMetadata({
    required this.requestId,
    this.extra,
    this.device,
  });

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        ...?extra,
        if (device != null) 'device': device,
      };
}

class VerifyRequest {
  final String country;
  final String idType;
  final String? idNumber;

  /// Attribution to the workflow this submission ran under. The server
  /// validates-and-drops a stale/foreign id — it never fails the submission.
  final String? workflowId;

  /// Liveness method (`gestures`/`flash`/`both`) — the server prices by it. Only
  /// sent for prop-configured mounts; a resolved workflow wins server-side.
  final String? livenessMode;

  /// The org's user reference → Entity.externalUserId at the seam (not matched).
  final String? userId;
  final VerifyUserData? userData;
  final VerifyMediaIds? mediaIds;

  /// Questionnaire answers (money fields include their `<key>_currency`
  /// companion). Validated server-side against the workflow's published
  /// definition; unknown keys dropped.
  final Map<String, dynamic>? questionnaire;

  /// The proof-of-address document type (`utility_bill` / `bank_statement` /
  /// `tenancy_agreement` / `other`), sent alongside `mediaIds.proofOfAddress`.
  final String? proofOfAddressType;

  /// Device Intelligence toggle — when false the server skips analysis + charge.
  final bool? deviceIntelligence;

  /// Contact-verification proof tokens (email/phone OTP).
  final VerifyContact? contact;

  /// eMRTD chip data (base64 DG1 + optional SOD). Dropped by the server for
  /// non-chip IDs; the SDK also only sends it for chip-capable selected IDs.
  final VerifyNfc? nfc;

  /// KYB registry block — present for business submissions (`idType` then
  /// carries the product key).
  final VerifyBusiness? business;

  /// `'business'` for KYB submissions (omitted for individual). The server
  /// derives the real subject type from the workflow; this is additive.
  final String? subjectType;
  final VerifyMetadata metadata;

  const VerifyRequest({
    required this.country,
    required this.idType,
    this.idNumber,
    this.workflowId,
    this.livenessMode,
    this.userId,
    this.userData,
    this.mediaIds,
    this.questionnaire,
    this.proofOfAddressType,
    this.deviceIntelligence,
    this.contact,
    this.nfc,
    this.business,
    this.subjectType,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'idType': idType,
        if (idNumber != null) 'idNumber': idNumber,
        if (workflowId != null) 'workflowId': workflowId,
        if (livenessMode != null) 'livenessMode': livenessMode,
        if (userId != null) 'userId': userId,
        if (userData != null) 'userData': userData!.toJson(),
        if (mediaIds != null && !mediaIds!.isEmpty) 'mediaIds': mediaIds!.toJson(),
        if (questionnaire != null && questionnaire!.isNotEmpty)
          'questionnaire': questionnaire,
        if (proofOfAddressType != null)
          'proofOfAddressType': proofOfAddressType,
        if (deviceIntelligence != null)
          'deviceIntelligence': deviceIntelligence,
        if (contact != null && !contact!.isEmpty) 'contact': contact!.toJson(),
        if (nfc != null) 'nfc': nfc!.toJson(),
        if (business != null) 'business': business!.toJson(),
        if (subjectType != null) 'subjectType': subjectType,
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

// ─── Contact verification (email / phone OTP) ────────────────────────────────

/// Response from `POST /api/kyc/contact/send`.
class ContactSendResponse {
  final String challengeId;
  final String? expiresAt;
  final String? deliveryChannel;

  const ContactSendResponse({
    required this.challengeId,
    this.expiresAt,
    this.deliveryChannel,
  });

  factory ContactSendResponse.fromJson(Map<String, dynamic> json) =>
      ContactSendResponse(
        challengeId: json['challengeId'] as String,
        expiresAt: json['expiresAt'] as String?,
        deliveryChannel: json['deliveryChannel'] as String?,
      );
}

/// Response from `POST /api/kyc/contact/check` — the single-use proof token.
class ContactCheckResponse {
  final bool verified;
  final String token;

  const ContactCheckResponse({required this.verified, required this.token});

  factory ContactCheckResponse.fromJson(Map<String, dynamic> json) =>
      ContactCheckResponse(
        verified: json['verified'] as bool? ?? false,
        token: json['token'] as String? ?? '',
      );
}

/// Contact-verification proof tokens attached to the verify body under
/// `contact`. Single-use; the server validates + claims them.
class VerifyContact {
  final String? emailToken;
  final String? phoneToken;

  const VerifyContact({this.emailToken, this.phoneToken});

  bool get isEmpty => emailToken == null && phoneToken == null;

  Map<String, dynamic> toJson() => {
        if (emailToken != null) 'emailToken': emailToken,
        if (phoneToken != null) 'phoneToken': phoneToken,
      };
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

  /// Display metadata for pairs the SDK has no curated definition for (Global
  /// Documents). All nullable — older servers omit them and the resolver falls
  /// back to a humanized label + document-capture default. See
  /// [resolveIdTypeDefinition].
  final String? label;
  final bool? requiresDocumentCapture;

  /// Raw scan-sides token from the server (`front_only` / `front_and_back`),
  /// parsed by [parseScanSides] in the resolver.
  final String? scanSides;

  /// Whether the document carries an eMRTD chip (intrinsic per-ID capability,
  /// catalogue-driven — not org-gated). Lets the SDK know when to offer the NFC
  /// chip step.
  final bool? supportsNfc;

  const SdkConfigIdType({
    required this.country,
    required this.idType,
    required this.features,
    this.label,
    this.requiresDocumentCapture,
    this.scanSides,
    this.supportsNfc,
  });

  factory SdkConfigIdType.fromJson(Map<String, dynamic> json) =>
      SdkConfigIdType(
        country: json['country'] as String,
        idType: json['idType'] as String,
        features: SdkIdTypeFeatures.fromJson(
          (json['features'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        label: json['label'] as String?,
        requiresDocumentCapture: json['requiresDocumentCapture'] as bool?,
        scanSides: json['scanSides'] as String?,
        supportsNfc: json['supportsNfc'] as bool?,
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

// ─── Workflow resolution (GET /api/kyc/workflows/:id) ────────────────────────

/// The template config carried by a resolved workflow. Only the keys the
/// Flutter SDK currently supports are parsed into typed fields; the full
/// untouched payload is kept in [raw] so later workstreams (country-select,
/// questionnaire, proof of address, NFC, liveness modes, device intelligence)
/// can read their keys as they land — no server round-trip changes.
class WorkflowFlowConfig {
  final String? subjectType;
  final String? country;
  final List<String>? idTypes;
  final bool? enableSelfie;
  final bool? enableDocumentCapture;
  final bool? allowDocumentUpload;
  final bool? enableLiveness;
  final bool? showThemeToggle;
  final bool? disableClose;
  final Map<String, dynamic>? appearance;
  final Map<String, dynamic>? consent;
  final Map<String, dynamic>? success;

  /// `bool` or `{ enabled, language }` — parsed by [VoiceGuidanceConfig.fromDynamic].
  final Object? voiceGuidance;
  final Map<String, dynamic> raw;

  const WorkflowFlowConfig({
    this.subjectType,
    this.country,
    this.idTypes,
    this.enableSelfie,
    this.enableDocumentCapture,
    this.allowDocumentUpload,
    this.enableLiveness,
    this.showThemeToggle,
    this.disableClose,
    this.appearance,
    this.consent,
    this.success,
    this.voiceGuidance,
    this.raw = const {},
  });

  factory WorkflowFlowConfig.fromJson(Map<String, dynamic> json) =>
      WorkflowFlowConfig(
        subjectType: json['subjectType'] as String?,
        country: json['country'] as String?,
        idTypes: (json['idTypes'] as List?)
            ?.map((e) => e as String)
            .toList(growable: false),
        enableSelfie: json['enableSelfie'] as bool?,
        enableDocumentCapture: json['enableDocumentCapture'] as bool?,
        allowDocumentUpload: json['allowDocumentUpload'] as bool?,
        enableLiveness: json['enableLiveness'] as bool?,
        showThemeToggle: json['showThemeToggle'] as bool?,
        disableClose: json['disableClose'] as bool?,
        appearance: (json['appearance'] as Map?)?.cast<String, dynamic>(),
        consent: (json['consent'] as Map?)?.cast<String, dynamic>(),
        success: (json['success'] as Map?)?.cast<String, dynamic>(),
        voiceGuidance: json['voiceGuidance'],
        raw: json,
      );
}

/// Response from `GET /api/kyc/workflows/:id` — one round trip hydrates the SDK
/// (config + granted idTypes + branding), so `/config` is skipped.
class WorkflowResolution {
  final String flowId;
  final String flowName;
  final int flowVersion;
  final WorkflowFlowConfig config;
  final String environment;
  final List<SdkConfigIdType> idTypes;
  final SdkConfigBranding? branding;

  const WorkflowResolution({
    required this.flowId,
    required this.flowName,
    required this.flowVersion,
    required this.config,
    required this.environment,
    required this.idTypes,
    this.branding,
  });

  factory WorkflowResolution.fromJson(Map<String, dynamic> json) {
    final flow = (json['flow'] as Map?)?.cast<String, dynamic>() ?? const {};
    return WorkflowResolution(
      flowId: flow['id'] as String? ?? '',
      flowName: flow['name'] as String? ?? '',
      flowVersion: (flow['version'] as num?)?.toInt() ?? 0,
      config: WorkflowFlowConfig.fromJson(
        (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
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
        'application/pdf' => 'pdf',
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

  // ── Workflow resolution — hydrate the SDK from a published flow ──────────────
  //
  // GET /api/kyc/workflows/:id. Auth: publishable key (Bearer pk_*). Returns the
  // flow config + granted idTypes + branding in one round trip, so /config is
  // skipped. A wrong org / environment / unpublished / unknown id is a uniform
  // 404 (mapped to `workflow_not_found` by the server).

  Future<WorkflowResolution> workflow(String workflowId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/workflows/${Uri.encodeComponent(workflowId)}',
      );
      return WorkflowResolution.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Contact verification — send + check an email/phone OTP ─────────────────

  /// Sends an OTP. [channel] is `email` | `phone`; [via] (`sms`/`whatsapp`) and
  /// [country] apply to phone. Returns the `challengeId` to check against.
  Future<ContactSendResponse> contactSend({
    required String channel,
    required String destination,
    String? country,
    String? via,
    int? codeLength,
    int? maxAttempts,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/contact/send',
        data: {
          'channel': channel,
          'destination': destination,
          if (country != null) 'country': country,
          if (via != null) 'via': via,
          if (codeLength != null) 'codeLength': codeLength,
          if (maxAttempts != null) 'maxAttempts': maxAttempts,
        },
        options: Options(contentType: 'application/json'),
      );
      return ContactSendResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Checks an OTP against a challenge. Returns the single-use proof `token`.
  Future<ContactCheckResponse> contactCheck({
    required String challengeId,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/contact/check',
        data: {'challengeId': challengeId, 'code': code},
        options: Options(contentType: 'application/json'),
      );
      return ContactCheckResponse.fromJson(response.data!);
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
