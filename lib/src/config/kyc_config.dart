import 'package:flutter/material.dart';
import 'id_types.dart';
import '../liveness/liveness_types.dart';

// ─── Environment ────────────────────────────────────────────────────────────

enum KYCEnvironment { development, staging, production }

// ─── Theme mode ─────────────────────────────────────────────────────────────

enum MyazaThemeMode { light, dark }

// ─── Appearance ─────────────────────────────────────────────────────────────

class MyazaKYCAppearance {
  /// Brand color — drives buttons, selected states, progress, the shield hero.
  /// Null falls back to the built-in theme primary (differs light/dark).
  final Color? primaryColor;

  /// Text/icon color rendered on top of [primaryColor] (e.g. button labels).
  final Color? primaryTextColor;

  /// Accent color for subtle fills/selected surfaces.
  final Color? accentColor;

  /// Modal background color.
  final Color? backgroundColor;

  /// Elevated surface color for cards/panels.
  final Color? surfaceColor;

  /// Border + input outline color.
  final Color? borderColor;

  /// Primary text color.
  final Color? textColor;

  final String companyName;

  /// Local asset path for the company logo (rendered with `Image.asset`).
  final String? logoAsset;

  /// Network logo URL to render in the header, or the literal `'default'` to
  /// use the org's own logo from the server config response. Takes precedence
  /// over [logoAsset].
  final String? logo;

  final MyazaThemeMode theme;

  const MyazaKYCAppearance({
    this.primaryColor,
    this.primaryTextColor,
    this.accentColor,
    this.backgroundColor,
    this.surfaceColor,
    this.borderColor,
    this.textColor,
    this.companyName = 'Myaza',
    this.logoAsset,
    this.logo,
    this.theme = MyazaThemeMode.light,
  });
}

// ─── Consent screen content ──────────────────────────────────────────────────

/// Overrides for the consent (welcome) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [MyazaKYCConfig.userData] (empty string when absent).
class KYCConsentContent {
  /// Heading. Defaults to `Welcome, {firstName}` when a first name is known,
  /// otherwise `Identity Verification`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in regulatory copy.
  final String? description;

  const KYCConsentContent({this.title, this.description});
}

// ─── Liveness config ────────────────────────────────────────────────────────

class LivenessConfig {
  final int challengeCount;
  final List<ChallengeConfig>? challengePool;
  final int timeoutPerChallenge;
  final bool enableAvatar;

  const LivenessConfig({
    this.challengeCount = 2,
    this.challengePool,
    this.timeoutPerChallenge = 8,
    this.enableAvatar = true,
  });
}

// ─── User data ───────────────────────────────────────────────────────────────

class UserData {
  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? phoneNumber;

  const UserData({
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.phoneNumber,
  });

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        gender: json['gender'] as String?,
        address: json['address'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      };
}

// ─── Main SDK config ────────────────────────────────────────────────────────

class MyazaKYCConfig {
  final String apiKey;
  final Country country;

  /// Target backend. Resolved to a base URL on mount: staging/production are
  /// hardcoded into the SDK; development uses [devUrl] (or a localhost default).
  final KYCEnvironment environment;

  /// Dev-only override for the base URL. Only used when [environment] is
  /// [KYCEnvironment.development]; ignored for staging/production. Defaults to a
  /// platform-aware localhost (`http://10.0.2.2:3001` on Android emulators,
  /// `http://localhost:3001` elsewhere).
  final String? devUrl;

  final List<IdType>? idTypes;
  final bool enableSelfie;
  final bool enableDocumentCapture;
  final bool enableLiveness;
  final MyazaKYCAppearance? appearance;

  /// Overrides for the consent (welcome) screen copy (title + description).
  final KYCConsentContent? consent;

  final Map<String, dynamic>? metadata;
  final LivenessConfig? livenessConfig;

  /// Pre-fills form fields and personalises the welcome screen.
  final UserData? userData;

  const MyazaKYCConfig({
    required this.apiKey,
    required this.country,
    this.environment = KYCEnvironment.production,
    this.devUrl,
    this.idTypes,
    this.enableSelfie = true,
    this.enableDocumentCapture = true,
    this.enableLiveness = true,
    this.appearance,
    this.consent,
    this.metadata,
    this.livenessConfig,
    this.userData,
  });
}

// ─── Submission callback ─────────────────────────────────────────────────────
//
// Fires immediately when the user completes the flow (the SDK has POSTed to
// /api/kyc/verify and got back 202 with { verificationId, status: 'pending' }).
// This does NOT mean verification is done — the final result arrives later via
// webhook to the org's backend, or via polling /api/kyc/status/:id.

class KYCSubmission {
  final String verificationId;
  /// Always 'pending' at this point.
  final String status;
  final Map<String, dynamic> metadata;
  final DateTime submittedAt;

  const KYCSubmission({
    required this.verificationId,
    required this.status,
    required this.metadata,
    required this.submittedAt,
  });
}

// ─── Error callback ──────────────────────────────────────────────────────────
//
// Fires only on TECHNICAL errors (network failure, invalid API key,
// insufficient credits, upload failure). It is NOT used for verification
// failures — those arrive asynchronously via webhook.

class KYCError {
  /// One of:
  ///   • 'network_error'         — connection failure / timeout
  ///   • 'invalid_api_key'       — server returned 401
  ///   • 'insufficient_credits'  — server returned 402
  ///   • 'upload_failed'         — /api/kyc/upload failed
  ///   • 'unknown'               — anything else
  final String code;
  final String message;
  /// For 'insufficient_credits': { required, balance, currency }.
  final Map<String, dynamic>? details;

  const KYCError({
    required this.code,
    required this.message,
    this.details,
  });
}
