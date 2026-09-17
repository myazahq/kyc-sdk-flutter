import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../nfc/emrtd_active_auth.dart';
import '../utils/map_tiles.dart' show MapLatLng;
import 'api_business.dart';

// Re-exported so callers keep a single view of the HTTP contract.
export 'api_business.dart';

// The Address Intelligence surface. Parts rather than sibling libraries
// because the calls need the private Dio client and error mapper.
part 'api_address.dart';
part 'api_address_calls.dart';

// ─── SDK version ─────────────────────────────────────────────────────────────
//
// Sent on every request as the X-SDK-Version header so the server can log
// which SDK versions are in the wild and gate breaking API changes by version.
// Keep in sync with pubspec.yaml `version`.

const String kSdkVersion = '3.0.1';

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
  static const addressPhoto = 'address_photo';
  static const businessDocument = 'business_document';
}

/// Response from `POST /api/kyc/upload` — the stored mediaId referenced later
/// in the verify request.
class UploadResponse {
  final String mediaId;

  const UploadResponse({required this.mediaId});

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      UploadResponse(mediaId: json['mediaId'] as String);
}

/// Response from `POST /api/kyc/document-capture/check`: what the server's
/// decision-time detectors made of one uploaded document side. `false` =
/// looked and found nothing (ask for a retake), `true` = fine, `null` = not
/// applicable or could not look (treated as fine).
class DocumentCaptureCheckResult {
  /// `front` | `back`.
  final String side;
  final bool? face;
  final bool? barcode;

  const DocumentCaptureCheckResult({
    required this.side,
    this.face,
    this.barcode,
  });

  factory DocumentCaptureCheckResult.fromJson(Map<String, dynamic> json) =>
      DocumentCaptureCheckResult(
        side: json['side'] is String ? json['side'] as String : '',
        // Anything but a real boolean is "could not look", never a problem.
        face: json['face'] is bool ? json['face'] as bool : null,
        barcode: json['barcode'] is bool ? json['barcode'] as bool : null,
      );
}

// ─── Verify ───────────────────────────────────────────────────────────────────

class VerifyUserData {
  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;

  /// The applicant's email, when the integrator passed one. Kept server-side as
  /// the address for any email the org has us send about a decision.
  final String? email;

  const VerifyUserData({this.firstName, this.lastName, this.dateOfBirth, this.email});

  Map<String, dynamic> toJson() => {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (email != null) 'email': email,
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
  final String? addressPhoto;

  const VerifyMediaIds({
    this.documentFront,
    this.documentBack,
    this.selfie,
    this.documentFrontVideo,
    this.documentBackVideo,
    this.livenessVideo,
    this.proofOfAddress,
    this.addressPhoto,
  });

  Map<String, dynamic> toJson() => {
        if (documentFront != null) 'documentFront': documentFront,
        if (documentBack != null) 'documentBack': documentBack,
        if (selfie != null) 'selfie': selfie,
        if (documentFrontVideo != null) 'documentFrontVideo': documentFrontVideo,
        if (documentBackVideo != null) 'documentBackVideo': documentBackVideo,
        if (livenessVideo != null) 'livenessVideo': livenessVideo,
        if (proofOfAddress != null) 'proofOfAddress': proofOfAddress,
        if (addressPhoto != null) 'addressPhoto': addressPhoto,
      };

  bool get isEmpty =>
      documentFront == null &&
      documentBack == null &&
      selfie == null &&
      documentFrontVideo == null &&
      documentBackVideo == null &&
      livenessVideo == null &&
      proofOfAddress == null &&
      addressPhoto == null;
}

/// Business (KYB) submission block — the registry lookup inputs. Sent instead of
/// media; the server derives the subject type from the (required) published KYB
/// workflow, not this block.
class VerifyBusiness {
  final String registrationNumber;
  final String? registrationName;
  final String? product;

  /// Contact email for key-people verification — the server emails this address
  /// the invite links when the workflow's `keyPeople.invite.channel` is 'email'
  /// and a role needs full KYC.
  final String? contactEmail;

  /// Company profile (collectCompanyInfo fields) — echoed on the org's webhook
  /// and address-matched against the registry record.
  final String? address;
  final String? email;
  final String? phone;
  final String? website;

  /// The five registry facts the applicant STATES, sent only when filled. The
  /// server drops any the workflow has switched off (validate-and-drop), and
  /// an under-send is what the required-field 422 is for.
  final String? dateOfIncorporation;
  final String? taxId;
  final String? vatNumber;
  final String? companyType;
  final String? natureOfBusiness;

  /// Uploaded supporting documents (`[{ type, mediaId }]`) — only honored when
  /// the workflow's `business.documents` block configures them.
  final List<Map<String, dynamic>>? documents;

  /// Applicant-declared directors & owners (≤20; `email` drives auto-sent
  /// invites). Only honored when the workflow sets `keyPeople.collect`.
  final List<Map<String, dynamic>>? keyPeople;

  /// The FATF fallback, attested: no natural person qualifies as a UBO.
  /// Branchable server-side as `keyPeople.uboUnidentifiable`; a claim, never a
  /// finding.
  final bool uboUnidentifiable;

  /// The applicant's declared role (+ optional name — the server backfills it
  /// from their verified KYC when absent).
  final Map<String, dynamic>? applicant;

  const VerifyBusiness({
    required this.registrationNumber,
    this.registrationName,
    this.product,
    this.contactEmail,
    this.address,
    this.email,
    this.phone,
    this.website,
    this.dateOfIncorporation,
    this.taxId,
    this.vatNumber,
    this.companyType,
    this.natureOfBusiness,
    this.documents,
    this.keyPeople,
    this.uboUnidentifiable = false,
    this.applicant,
  });

  static bool _has(String? v) => v != null && v.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'registrationNumber': registrationNumber,
        if (_has(registrationName)) 'registrationName': registrationName,
        if (product != null) 'product': product,
        if (_has(contactEmail)) 'contactEmail': contactEmail,
        if (_has(address)) 'address': address,
        if (_has(email)) 'email': email,
        if (_has(phone)) 'phone': phone,
        if (_has(website)) 'website': website,
        if (_has(dateOfIncorporation)) 'dateOfIncorporation': dateOfIncorporation,
        if (_has(taxId)) 'taxId': taxId,
        if (_has(vatNumber)) 'vatNumber': vatNumber,
        if (_has(companyType)) 'companyType': companyType,
        if (_has(natureOfBusiness)) 'natureOfBusiness': natureOfBusiness,
        if (documents != null && documents!.isNotEmpty) 'documents': documents,
        if (keyPeople != null && keyPeople!.isNotEmpty) 'keyPeople': keyPeople,
        if (uboUnidentifiable) 'uboUnidentifiable': true,
        if (applicant != null) 'applicant': applicant,
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

  /// The OPTIONAL groups: the displayed signature image (DG7) and additional
  /// personal / document details (DG11 / DG12). Verified against the SOD like
  /// DG2; recorded on the result, never decisive.
  final String? dg7;
  final String? dg11;
  final String? dg12;

  /// DG15 (the chip's ACTIVE-AUTHENTICATION public key), its signature over the
  /// challenge the server issued, and which challenge that was — the ANTI-CLONE
  /// proof. Passive authentication says the issuing state signed this data;
  /// only these say it is the chip they signed it onto. Verified server-side
  /// against a SOD-bound DG15, never here: a client that checked its own chip
  /// could be patched to say yes.
  final String? dg15;
  final String? aaSignature;
  final String? aaChallengeId;

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
    this.dg7,
    this.dg11,
    this.dg12,
    this.dg15,
    this.aaSignature,
    this.aaChallengeId,
    this.chipAuth = 'bac',
    this.paceOutcome,
    this.paceDetail,
  });

  Map<String, dynamic> toJson() => {
        'dg1': dg1,
        if (sod != null) 'sod': sod,
        if (dg2 != null) 'dg2': dg2,
        // The optional groups. Hash-verified server-side against the SOD like
        // DG2; recorded, never decisive.
        if (dg7 != null) 'dg7': dg7,
        if (dg11 != null) 'dg11': dg11,
        if (dg12 != null) 'dg12': dg12,
        // The anti-clone proof. Sent only when the chip actually signed.
        if (dg15 != null) 'dg15': dg15,
        if (aaSignature != null) 'aaSignature': aaSignature,
        if (aaChallengeId != null) 'aaChallengeId': aaChallengeId,
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

  /// The attempt session this run happened under — the verification adopts its
  /// id, and a registry check paid at selection is not paid again at submit.
  final String? sessionId;

  /// Attribution to the workflow this submission ran under. The server
  /// validates-and-drops a stale/foreign id — it never fails the submission.
  final String? workflowId;

  /// Liveness method (`gestures`/`flash`/`both`) — the server prices by it. Only
  /// sent for prop-configured mounts; a resolved workflow wins server-side.
  final String? livenessMode;

  /// Multi-ID: every check in the run, in pick order (2–3). ONE verification
  /// comes back, judged by the workflow's pass policy. The top-level
  /// `idType`/`idNumber` mirror the first entry, so anything reading a
  /// verification's own ID keeps one meaning.
  final List<Map<String, dynamic>>? idChecks;

  /// The org's user reference → Entity.externalUserId at the seam (not matched).
  final String? userId;
  final VerifyUserData? userData;
  final VerifyMediaIds? mediaIds;

  /// Questionnaire answers (money fields include their `<key>_currency`
  /// companion). Validated server-side against the workflow's published
  /// definition; unknown keys dropped.
  final Map<String, dynamic>? questionnaire;

  /// The proof-of-address document type (`utility_bill` / `bank_statement` /
  /// `tenancy_agreement` / `government_document` / `other`), sent alongside
  /// `mediaIds.proofOfAddress`.
  final String? proofOfAddressType;

  /// Address Intelligence — the smart-address block (pin + optional directions
  /// + device fix), when the address-collection step gathered one. On a KYB
  /// submission the pin is the business premises. Built by `addressPayload`.
  final Map<String, dynamic>? address;

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
    this.sessionId,
    this.workflowId,
    this.livenessMode,
    this.userId,
    this.userData,
    this.mediaIds,
    this.questionnaire,
    this.proofOfAddressType,
    this.address,
    this.deviceIntelligence,
    this.contact,
    this.nfc,
    this.idChecks,
    this.business,
    this.subjectType,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'idType': idType,
        if (idNumber != null) 'idNumber': idNumber,
        if (idChecks != null && idChecks!.isNotEmpty) 'idChecks': idChecks,
        if (sessionId != null) 'sessionId': sessionId,
        if (workflowId != null) 'workflowId': workflowId,
        if (livenessMode != null) 'livenessMode': livenessMode,
        if (userId != null) 'userId': userId,
        if (userData != null) 'userData': userData!.toJson(),
        if (mediaIds != null && !mediaIds!.isEmpty) 'mediaIds': mediaIds!.toJson(),
        if (questionnaire != null && questionnaire!.isNotEmpty)
          'questionnaire': questionnaire,
        if (proofOfAddressType != null)
          'proofOfAddressType': proofOfAddressType,
        if (address != null && address!.isNotEmpty) 'address': address,
        if (deviceIntelligence != null)
          'deviceIntelligence': deviceIntelligence,
        if (contact != null && !contact!.isEmpty) 'contact': contact!.toJson(),
        if (nfc != null) 'nfc': nfc!.toJson(),
        if (business != null) 'business': business!.toJson(),
        if (subjectType != null) 'subjectType': subjectType,
        'metadata': metadata.toJson(),
      };
}

/// One key person the server minted an invite link for (KYB submissions where
/// a role resolves to full KYC).
/// One person a submitted KYB application is still waiting on.
///
/// The SERVER's view, not the applicant's: registry discovery runs AFTER
/// submission and can add directors the applicant never listed, so the invite
/// links returned at submit are only ever a first draft.
class AwaitingPerson {
  final String id;
  final String name;
  final String role;
  final double? ownershipPct;

  /// ISO-2, or null when the register gave free text no flag matches.
  final String? country;

  /// One of `verified` | `failed` | `submitted` | `pending` | `not_needed`.
  final String status;

  /// Null once their check is done, or when they never needed one.
  final String? inviteUrl;
  final bool isApplicant;

  /// A company completes a KYB application, not a KYC — the list labels it so.
  final bool isCorporate;

  const AwaitingPerson({
    required this.id,
    required this.name,
    required this.role,
    this.ownershipPct,
    this.country,
    required this.status,
    this.inviteUrl,
    this.isApplicant = false,
    this.isCorporate = false,
  });

  /// Still owes a check — drives whether the list keeps refreshing.
  bool get stillOwes =>
      status == 'pending' || status == 'submitted' || status == 'failed';

  factory AwaitingPerson.fromJson(Map<String, dynamic> json) => AwaitingPerson(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        ownershipPct: (json['ownershipPct'] as num?)?.toDouble(),
        country: json['country'] as String?,
        status: json['status'] as String? ?? 'pending',
        inviteUrl: json['inviteUrl'] as String?,
        isApplicant: json['isApplicant'] as bool? ?? false,
        isCorporate: json['isCorporate'] as bool? ?? false,
      );
}

/// The completed-session summary: who the application is waiting on, and
/// whether the server has finished reconciling that list.
class SessionSummaryResponse {
  /// False while registry discovery is still reconciling the people list. A
  /// list rendered before it settles is one director short, permanently.
  final bool keyPeopleSettled;
  final List<AwaitingPerson> keyPeople;

  const SessionSummaryResponse({
    required this.keyPeopleSettled,
    required this.keyPeople,
  });

  factory SessionSummaryResponse.fromJson(Map<String, dynamic> json) =>
      SessionSummaryResponse(
        // Absent means an older server that never reconciled — treat as settled
        // rather than spinning forever on a field it will never send.
        keyPeopleSettled: json['keyPeopleSettled'] as bool? ?? true,
        keyPeople: ((json['keyPeople'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AwaitingPerson.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class KeyPersonInvite {
  final String keyPersonId;
  final String name;
  final String inviteUrl;

  const KeyPersonInvite({
    required this.keyPersonId,
    required this.name,
    required this.inviteUrl,
  });

  factory KeyPersonInvite.fromJson(Map<String, dynamic> json) =>
      KeyPersonInvite(
        keyPersonId: (json['keyPersonId'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        inviteUrl: (json['inviteUrl'] ?? '').toString(),
      );
}

/// `POST /session/start` — mint (or resume) an attempt session.
class SessionStartResponse {
  final String sessionId;
  final bool resumed;

  /// Where the user got to, when resuming: `{ step, mediaIds, data }` — the
  /// snapshot progressFromState wrote, replayed by session_restore.dart.
  /// Media references are already pruned server-side of anything expired.
  final Map<String, dynamic>? progress;

  /// The session's own hosted web page. After a KYB submission it is the
  /// rehydrated success screen with every key person's invite link — the
  /// applicant's way back to those links once the app closes.
  final String? url;

  const SessionStartResponse({
    required this.sessionId,
    required this.resumed,
    this.progress,
    this.url,
  });

  factory SessionStartResponse.fromJson(Map<String, dynamic> json) =>
      SessionStartResponse(
        sessionId: json['sessionId'] as String,
        resumed: json['resumed'] == true,
        progress: (json['progress'] as Map?)?.cast<String, dynamic>(),
        url: json['url'] as String?,
      );
}

class VerifyResponse {
  final String verificationId;
  final String status; // Always 'pending' immediately after submission

  /// KYB with applicant verification: the KeyPerson row the server created for
  /// the applicant. The applicant's OWN individual submission carries this as
  /// `metadata.userId` — the link back to the application.
  final String? applicantKeyPersonId;

  /// Invite links minted for full-KYC key people (empty when none).
  final List<KeyPersonInvite> keyPeopleInvites;

  const VerifyResponse({
    required this.verificationId,
    required this.status,
    this.applicantKeyPersonId,
    this.keyPeopleInvites = const [],
  });

  factory VerifyResponse.fromJson(Map<String, dynamic> json) {
    final invites = json['keyPeopleInvites'];
    return VerifyResponse(
      verificationId: json['verificationId'] as String,
      status: json['status'] as String,
      applicantKeyPersonId: json['applicantKeyPersonId'] as String?,
      keyPeopleInvites: invites is List
          ? invites
              .whereType<Map>()
              .map((e) => KeyPersonInvite.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
    );
  }
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

  /// The one status vocabulary: 'not_started' | 'in_progress' | 'processing' |
  /// 'in_review' | 'awaiting_resubmission' | 'approved' | 'declined' |
  /// 'abandoned' | 'expired' | 'error'.
  ///
  /// What HAPPENED. [checkStatus] beside it is what the checks found, and the
  /// two differ when a person overrode the automated result: 'approved' with a
  /// checkStatus of 'failed' means somebody accepted the applicant despite a
  /// failed check, and [reason] says what they accepted them despite.
  final String status;

  /// What the CHECKS found: 'pending' | 'verified' | 'failed' | 'not_found' |
  /// 'error'. Never moves once they finish, whatever anybody decides after.
  final String? checkStatus;
  final String? reason;

  /// The stable machine token beside [reason] (e.g. `biometric_auth_failed`),
  /// null on success.
  final String? reasonCode;
  final StatusResult? result;
  final DateTime createdAt;
  final DateTime? completedAt;

  const StatusResponse({
    required this.verificationId,
    required this.status,
    this.checkStatus,
    this.reason,
    this.reasonCode,
    this.result,
    required this.createdAt,
    this.completedAt,
  });

  /// Still running the checks.
  ///
  /// Compares against 'processing', which is what the server now calls this
  /// state. It said 'pending' before the status vocabulary merged, and leaving
  /// the old value here would have made every verification look instantly
  /// finished the moment it was submitted.
  bool get isPending => status == 'processing';

  /// The checks have finished. A verification a workflow routed to a person
  /// ('in_review') counts as complete here: the checks ARE done, and an SDK
  /// must not sit polling for however long a human takes to answer.
  bool get isComplete => !isPending;

  factory StatusResponse.fromJson(Map<String, dynamic> json) => StatusResponse(
        verificationId: json['verificationId'] as String,
        status: json['status'] as String,
        checkStatus: json['checkStatus'] as String?,
        reason: json['reason'] as String?,
        reasonCode: json['reasonCode'] as String?,
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

  /// The visitor's country, resolved from their IP.
  ///
  /// A GUESS and only ever a DEFAULT — nothing branches on it and it never
  /// reaches a verification. Deliberately not evidence: device intelligence
  /// carries the same lookup as a RISK signal, and the two must not be confused.
  final String? geoCountry;

  /// Whether the platform's forward address search is available at all. The
  /// address flow offers its search step only when it is.
  final bool addressSearch;

  /// Which search backend answers: `autocomplete` (Places, as-you-type) or
  /// `basic` (explicit submit). Absent when [addressSearch] is false. The two
  /// are chosen by this flag, never by trying one and falling back.
  final String? addressSearchMode;

  /// The framed Google-map picker page (our hosted /embed/map plus a signed
  /// APP grant), for a WebView. Null when the platform holds no Maps key —
  /// the built-in OSM picker is the fallback every map failure degrades to.
  /// `googleMapsBrowserKey` is deliberately still NOT parsed: the key is the
  /// hosted page's alone, and Street View entrance framing does not exist here.
  final String? mapsFrameUrl;

  const SdkConfigResponse({
    required this.environment,
    required this.idTypes,
    this.branding,
    this.geoCountry,
    this.addressSearch = false,
    this.addressSearchMode,
    this.mapsFrameUrl,
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
        geoCountry: json['geoCountry'] as String?,
        addressSearch: json['addressSearch'] == true,
        addressSearchMode: json['addressSearchMode'] as String?,
        mapsFrameUrl: json['mapsFrameUrl'] as String?,
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
  final bool? allowDocumentScan;
  final bool? enableLiveness;
  final bool? showThemeToggle;
  /// Raw wire value; parsed by MyazaProgressStyle.fromJson at merge time.
  final String? progressStyle;
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
    this.allowDocumentScan,
    this.enableLiveness,
    this.showThemeToggle,
    this.progressStyle,
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
        allowDocumentScan: json['allowDocumentScan'] as bool?,
        enableLiveness: json['enableLiveness'] as bool?,
        showThemeToggle: json['showThemeToggle'] as bool?,
        progressStyle: json['progressStyle'] as String?,
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

  /// KYB only: the mapped applicant workflow (business.applicant.workflowId),
  /// resolved server-side. Null when absent or dangling.
  final ApplicantWorkflow? applicantWorkflow;

  /// The same address-capability facts `/api/kyc/config` serves, mirrored on
  /// the workflow resolution BECAUSE a workflow mount skips `/config`: without
  /// them a workflow embed silently lost the search step, the framed Google
  /// map, the Street View framer and the geo default while a prop-configured
  /// mount kept all four (the React Native gate had them; this one did not,
  /// user report 2026-09-08). A field added to `/config` that a mount needs
  /// must be added here too.
  final String? geoCountry;
  final bool addressSearch;
  final String? addressSearchMode;
  final String? mapsFrameUrl;

  const WorkflowResolution({
    required this.flowId,
    required this.flowName,
    required this.flowVersion,
    required this.config,
    required this.environment,
    required this.idTypes,
    this.branding,
    this.applicantWorkflow,
    this.geoCountry,
    this.addressSearch = false,
    this.addressSearchMode,
    this.mapsFrameUrl,
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
      applicantWorkflow: json['applicantWorkflow'] is Map
          ? ApplicantWorkflow.fromJson(
              (json['applicantWorkflow'] as Map).cast<String, dynamic>())
          : null,
      geoCountry: json['geoCountry'] as String?,
      addressSearch: json['addressSearch'] == true,
      addressSearchMode: json['addressSearchMode'] as String?,
      mapsFrameUrl: json['mapsFrameUrl'] as String?,
    );
  }
}

/// A KYB workflow's mapped APPLICANT workflow (business.applicant.workflowId):
/// the individual workflow whose capture template overlays the applicant's own
/// KYC leg, and whose id is stamped on that submission.
class ApplicantWorkflow {
  final String id;
  final String name;
  final int version;
  /// The mapped workflow's published config, untouched — the overlay reads
  /// only the capture-leg keys it knows.
  final Map<String, dynamic> config;

  const ApplicantWorkflow({
    required this.id,
    required this.name,
    required this.version,
    required this.config,
  });

  factory ApplicantWorkflow.fromJson(Map<String, dynamic> json) =>
      ApplicantWorkflow(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
        config: (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
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

  // ── Document capture check — can the server read this side? ──────────────
  //
  // Runs an uploaded document side through the detectors the server later
  // decides with (a face on the printed photo, a readable barcode), so the
  // applicant can retake a photo now rather than be declined later.
  //
  // Best-effort by contract: any error, any non-200 and anything slower than
  // [_kCaptureCheckTimeout] returns null, which the flow reads as "no problem".
  // The check can ask for a retake; it can never block or fail the flow.

  static const Duration _kCaptureCheckTimeout = Duration(seconds: 8);

  Future<DocumentCaptureCheckResult?> checkDocumentCapture({
    required String mediaId,
    required String side,
    required String country,
    required String idType,
    String? workflowId,
    String? sessionId,
  }) async {
    final cancel = CancelToken();
    try {
      final response = await _dio
          .post<Map<String, dynamic>>(
            '/api/kyc/document-capture/check',
            data: {
              'mediaId': mediaId,
              'side': side,
              'country': country,
              'idType': idType,
              if (workflowId != null) 'workflowId': workflowId,
              if (sessionId != null) 'sessionId': sessionId,
            },
            cancelToken: cancel,
            options: Options(
              contentType: 'application/json',
              sendTimeout: _kCaptureCheckTimeout,
              receiveTimeout: _kCaptureCheckTimeout,
            ),
          )
          // Dio's timeouts bound each phase; this bounds the whole call,
          // connecting included (the client's connect timeout is 30s).
          .timeout(_kCaptureCheckTimeout);
      final data = response.data;
      if (response.statusCode != 200 || data == null) return null;
      final result = DocumentCaptureCheckResult.fromJson(data);
      // Attributed to the side asked about: that is the photo the mediaId is.
      return result.side == side
          ? result
          : DocumentCaptureCheckResult(
              side: side, face: result.face, barcode: result.barcode);
    } catch (_) {
      // Stops a request the timeout abandoned; harmless on one already done.
      cancel.cancel();
      return null;
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

  // ── Attempt sessions ──────────────────────────────────────────────────────
  //
  // Best-effort by contract: sessions power resumability, the dashboard's
  // live attempt view, and the registry check at selection. Verifying is
  // never conditional on one existing, so callers swallow failures.

  /// Mint (or resume) the attempt session this run is recorded under.
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    /// The same device block the submission sends, so the dashboard's
    /// in-progress row shows the device and SDK from the moment the SDK loads
    /// rather than after the applicant finishes (2026-09-08).
    Map<String, dynamic>? device,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/session/start',
        data: {
          if (externalUserId != null) 'externalUserId': externalUserId,
          if (deviceRef != null) 'deviceRef': deviceRef,
          if (workflowId != null) 'workflowId': workflowId,
          if (device != null) 'device': device,
        },
        options: Options(contentType: 'application/json'),
      );
      return SessionStartResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Save where the user has got to. Losing a save costs some re-typing on a
  /// future resume, never anything now.
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {
    try {
      await _dio.put<void>(
        '/api/kyc/session/${Uri.encodeComponent(sessionId)}/progress',
        data: progress,
        options: Options(contentType: 'application/json'),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// The PAID registry check for the company the applicant identified, run at
  /// selection so the register's key people come back BEFORE the form asks
  /// for them. Never fails the flow: a short balance or a spent lookup budget
  /// returns `checked: false` and the lookup happens at submit as before.
  Future<BusinessSelectResponse> businessSelect({
    required String sessionId,
    required String country,
    required String registrationNumber,
    String? subdivisionCode,
    String? registrationName,
    String? product,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/kyc/business/select',
        data: {
          'sessionId': sessionId,
          'country': country,
          'registrationNumber': registrationNumber,
          if (subdivisionCode != null && subdivisionCode.isNotEmpty)
            'subdivisionCode': subdivisionCode,
          if (registrationName != null && registrationName.isNotEmpty)
            'registrationName': registrationName,
          if (product != null) 'product': product,
        },
        options: Options(contentType: 'application/json'),
      );
      return BusinessSelectResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Find a business by name. FREE — no provider charge here or upstream, so
  /// the applicant may look as many times as they need. Throws on a provider
  /// failure so the caller can show "unavailable" rather than an empty list,
  /// which would read as "this business is not registered".
  Future<BusinessSearchResponse> businessSearch({
    required String country,
    required String query,
    String? subdivisionCode,
    int? limit,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/business/search',
        queryParameters: {
          'country': country,
          'query': query,
          if (subdivisionCode != null && subdivisionCode.isNotEmpty)
            'subdivisionCode': subdivisionCode,
          if (limit != null) 'limit': limit,
        },
      );
      return BusinessSearchResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Registry regions for a country. Empty when it has a single register.
  Future<BusinessRegionsResponse> businessRegions(String country) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/business/regions',
        queryParameters: {'country': country},
      );
      return BusinessRegionsResponse.fromJson(response.data!);
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

  /// The completed-session summary — who this application is still waiting on.
  ///
  /// Read AFTER submission: the invite links returned at submit are the
  /// applicant's own list, and registry discovery can add people to it.
  Future<SessionSummaryResponse> sessionSummary(String sessionId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/session/${Uri.encodeComponent(sessionId)}/summary',
      );
      return SessionSummaryResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// A fresh Active-Authentication challenge for a chip read — the nonce the
  /// chip signs to prove it is the original document rather than a copy of one.
  ///
  /// It has to come from the SERVER: a nonce the client chose would let a
  /// captured signature be replayed forever, which is the clone the check
  /// exists to catch. Best-effort at every call site — a chip read without one
  /// is exactly the read this SDK did before Active Authentication existed.
  Future<AaChallenge> nfcChallenge() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api/kyc/nfc/challenge');
      final body = response.data!;
      return AaChallenge(
        id: body['challengeId'] as String,
        bytes: base64.decode(body['challenge'] as String),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

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
      // 422 contact_verification_required carries `missing` (email | phone) —
      // what submit recovery routes on.
      if (statusCode == 422 && data['missing'] is List) {
        details = {'missing': data['missing']};
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
