import 'package:flutter/material.dart';
import '../liveness/liveness_types.dart';
import 'business.dart';
import 'contact_verification.dart';
import 'nfc_config.dart';
import 'address_collection.dart';
import 'proof_of_address.dart';
import 'questionnaire.dart';
import '../providers/step_resubmit.dart';
import 'multi_id.dart';
import 'biometric_options.dart';

// ─── Environment ────────────────────────────────────────────────────────────

enum KYCEnvironment { development, sandbox, production }

// ─── Theme mode ─────────────────────────────────────────────────────────────

/// `system` follows the device's platform brightness (live).
enum MyazaThemeMode { light, dark, system }

/// How flow progress is drawn — see [MyazaKYCConfig.progressStyle].
enum MyazaProgressStyle {
  /// Numbered circles, one per step.
  steps,

  /// A thin bar on the header's bottom edge.
  bar,

  /// No progress element in the header at all. The brand row and controls
  /// stay; only the step circles / bar are dropped.
  none;

  /// Parse the wire value a published workflow carries. Anything unrecognised
  /// falls back to [steps] rather than throwing: a newer server adding a fourth
  /// style must not break an older SDK.
  static MyazaProgressStyle fromJson(String? value) => switch (value) {
        'bar' => MyazaProgressStyle.bar,
        'none' => MyazaProgressStyle.none,
        _ => MyazaProgressStyle.steps,
      };
}

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

  /// Corner radius in px for buttons, inputs and cards. The whole radius scale
  /// derives from it, so 0 squares the flow off and 20 softens it. Circular
  /// elements (avatars, the camera oval) are never affected. Null = the SDK
  /// default (12).
  final double? borderRadius;

  /// Body font family. Resolved through `google_fonts` by name, so any Google
  /// font works; an unknown name falls back to a family bundled by the host app,
  /// then to the SDK default. Null = Karla.
  final String? fontFamily;

  /// Heading font family. Falls back to [fontFamily], then to Space Grotesk.
  final String? headingFontFamily;

  /// Colour overrides applied only in DARK mode.
  ///
  /// The colours above are the LIGHT palette. Without this the appearance is
  /// applied on top of whichever base scheme is active, so an org's light
  /// background simply overwrote the dark one and the theme toggle stopped
  /// working for any branded flow.
  final MyazaKYCAppearance? dark;

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
    this.borderRadius,
    this.fontFamily,
    this.headingFontFamily,
    this.dark,
    this.theme = MyazaThemeMode.light,
  });

  /// The palette for [isDark], with the dark overrides folded in when present.
  /// Returns `this` unchanged in light mode, or when no dark block was given.
  MyazaKYCAppearance forBrightness(bool isDark) {
    final d = dark;
    if (!isDark || d == null) return this;
    return MyazaKYCAppearance(
      primaryColor: d.primaryColor ?? primaryColor,
      primaryTextColor: d.primaryTextColor ?? primaryTextColor,
      accentColor: d.accentColor ?? accentColor,
      backgroundColor: d.backgroundColor ?? backgroundColor,
      surfaceColor: d.surfaceColor ?? surfaceColor,
      borderColor: d.borderColor ?? borderColor,
      textColor: d.textColor ?? textColor,
      // Non-colour settings never differ by mode.
      companyName: companyName,
      logoAsset: logoAsset,
      logo: logo,
      borderRadius: borderRadius,
      fontFamily: fontFamily,
      headingFontFamily: headingFontFamily,
      theme: theme,
    );
  }

  /// Shallow-merges a resolved workflow's `appearance` map over [base]
  /// (flow keys win per-field, matching the web SDK's shallow appearance
  /// merge). Colors are hex strings (`#5645F5`); `theme` is
  /// `'light'`/`'dark'`/`'system'`.
  /// Returns [base] unchanged when [flow] is null/empty.
  static MyazaKYCAppearance? mergeFromJson(
    MyazaKYCAppearance? base,
    Map<String, dynamic>? flow,
  ) {
    if (flow == null || flow.isEmpty) return base;
    final b = base ?? const MyazaKYCAppearance();
    final themeStr = (flow['theme'] as String?)?.toLowerCase();
    return MyazaKYCAppearance(
      primaryColor: parseHexColor(flow['primaryColor']) ?? b.primaryColor,
      primaryTextColor:
          parseHexColor(flow['primaryTextColor']) ?? b.primaryTextColor,
      accentColor: parseHexColor(flow['accentColor']) ?? b.accentColor,
      backgroundColor:
          parseHexColor(flow['backgroundColor']) ?? b.backgroundColor,
      surfaceColor: parseHexColor(flow['surfaceColor']) ?? b.surfaceColor,
      borderColor: parseHexColor(flow['borderColor']) ?? b.borderColor,
      textColor: parseHexColor(flow['textColor']) ?? b.textColor,
      companyName: (flow['companyName'] as String?) ?? b.companyName,
      logoAsset: b.logoAsset,
      logo: (flow['logo'] as String?) ?? b.logo,
      // num, not double: JSON decodes 12 as int and 12.0 as double.
      borderRadius: (flow['borderRadius'] as num?)?.toDouble() ?? b.borderRadius,
      fontFamily: (flow['fontFamily'] as String?) ?? b.fontFamily,
      headingFontFamily:
          (flow['headingFontFamily'] as String?) ?? b.headingFontFamily,
      dark: flow['dark'] is Map<String, dynamic>
          ? MyazaKYCAppearance.mergeFromJson(
              b.dark ?? const MyazaKYCAppearance(),
              flow['dark'] as Map<String, dynamic>,
            )
          : b.dark,
      theme: switch (themeStr) {
        'dark' => MyazaThemeMode.dark,
        'light' => MyazaThemeMode.light,
        'system' => MyazaThemeMode.system,
        _ => b.theme,
      },
    );
  }
}

/// Parses a `#RRGGBB` / `#AARRGGBB` (or without the `#`) hex string into a
/// [Color]. Returns null for null/blank/malformed input so callers keep their
/// existing value.
Color? parseHexColor(Object? value) {
  if (value is! String) return null;
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(n);
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

  factory KYCConsentContent.fromJson(Map<String, dynamic> json) =>
      KYCConsentContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

// ─── Success screen content ──────────────────────────────────────────────────

/// Overrides for the success (submitted) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [MyazaKYCConfig.userData] (empty string when absent).
class KYCSuccessContent {
  /// Heading. Defaults to `Verification Submitted!`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in "submitted for
  /// review" copy.
  final String? description;

  const KYCSuccessContent({this.title, this.description});

  factory KYCSuccessContent.fromJson(Map<String, dynamic> json) =>
      KYCSuccessContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
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

// ─── Voice guidance config ────────────────────────────────────────────────────

/// Configuration for the spoken liveness instructions ("nod your head",
/// "blink", …). This is text-to-speech **output** played to the user for
/// accessibility — it never records audio, so no microphone permission is
/// involved.
///
/// Structured as an object (rather than a bare boolean) so a [language] can be
/// added without a breaking change — Myaza operates across NG/GH/KE/ZA/CI, and
/// French guidance for CI is a likely future need. Mirrors the web SDK's
/// `VoiceGuidanceConfig`.
class VoiceGuidanceConfig {
  /// Whether spoken guidance plays. Default `true` (on for accessibility).
  final bool enabled;

  /// BCP-47 language tag for the spoken voice (e.g. `'en-US'`, `'fr-FR'`).
  /// Defaults to `'en-US'`. Currently selects the TTS voice only; the spoken
  /// text still mirrors the on-screen English instruction (localized strings
  /// are a planned follow-up).
  final String? language;

  const VoiceGuidanceConfig({this.enabled = true, this.language});

  /// Resolved BCP-47 language, defaulting to `en-US`.
  String get resolvedLanguage => language ?? 'en-US';

  /// Convenience: a config that disables spoken guidance.
  static const VoiceGuidanceConfig off = VoiceGuidanceConfig(enabled: false);

  /// Parses a resolved workflow's `voiceGuidance` value, which may be a bare
  /// bool (`true`/`false`) or an object (`{ enabled?, language? }`). Returns
  /// null for anything unrecognized so the caller keeps its existing value.
  static VoiceGuidanceConfig? fromDynamic(Object? value) {
    if (value is bool) return VoiceGuidanceConfig(enabled: value);
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      return VoiceGuidanceConfig(
        enabled: map['enabled'] as bool? ?? true,
        language: map['language'] as String?,
      );
    }
    return null;
  }
}

// ─── User data ───────────────────────────────────────────────────────────────

class UserData {
  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? phoneNumber;

  /// The business's display name, for `{businessName}` tokens in consent copy
  /// on KYB flows. Registration details aren't collected until after consent,
  /// so this resolves only when the integrator passes it in — mirrors the web
  /// SDK. Display-only: never submitted.
  final String? businessName;

  const UserData({
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.phoneNumber,
    this.businessName,
  });

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        gender: json['gender'] as String?,
        address: json['address'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        businessName: json['businessName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        // businessName is deliberately NOT serialized — it is consent-copy
        // display data, not verification input.
      };
}

// ─── Multi-region country option ──────────────────────────────────────────────

/// One offered country in a multi-region workflow. When a config carries more
/// than one, the SDK inserts a country-select step; the picked entry's
/// [idTypes] (when set) narrow the ID picker for that country.
class WorkflowCountryOption {
  /// ISO-3166 alpha-2 code.
  final String country;

  /// Per-country ID-type subset (null/empty = every granted ID for the country).
  final List<String>? idTypes;

  /// Multi-ID: which IDs THIS country offers for each check in the run. A
  /// pinned entry keeps its list; an absent one offers everything.
  final List<List<String>?>? multiIdSlots;

  const WorkflowCountryOption({
    required this.country,
    this.idTypes,
    this.multiIdSlots,
  });

  factory WorkflowCountryOption.fromJson(Map<String, dynamic> json) =>
      WorkflowCountryOption(
        country: json['country'] as String,
        idTypes: (json['idTypes'] as List?)
            ?.map((e) => e as String)
            .toList(growable: false),
        multiIdSlots: (json['multiIdSlots'] as List?)
            ?.map((slot) => (slot is Map<String, dynamic>
                    ? (slot['idTypes'] as List?)
                        ?.map((e) => e as String)
                        .toList(growable: false)
                    : null))
            .toList(growable: false),
      );
}

// ─── Main SDK config ────────────────────────────────────────────────────────

class MyazaKYCConfig {
  /// Bearer token sent on every request. The key prefix is the single source of
  /// truth for the environment — the SDK derives it (and the base URL)
  /// automatically: `pk_dev_…` → development, `pk_test_…` → sandbox,
  /// `pk_live_…` → production. An unrecognized prefix throws on mount.
  final String apiKey;

  /// ISO-3166 alpha-2 country code (e.g. `'NG'`). Any granted ISO country is
  /// accepted — the SDK is no longer limited to the gov-DB provider countries
  /// (Global Documents). The org's grants gate what's actually available.
  ///
  /// OPTIONAL when [workflowId] is set — the resolved workflow supplies it (and
  /// wins over this value). Mirrors the React SDK, where `country?: C` is
  /// "required unless workflowId is set".
  ///
  /// It was `required` while this comment already claimed it could be omitted, so
  /// the documented mount did not compile: a workflow user had to invent a country
  /// purely to satisfy the constructor, then watch the workflow overwrite it.
  ///
  /// Null only in the window before the merge. `effectiveCountry` is what the flow
  /// reads, and the launcher refuses to mount without one.
  final String? country;

  /// Run from a published dashboard workflow (`wf_…`). The SDK resolves it via
  /// `GET /api/kyc/workflows/:id` on launch and the **flow config wins** over
  /// overlapping props (country, idTypes, step toggles, appearance, consent,
  /// success copy, …). Runtime data (userId, userData, metadata, callbacks)
  /// always stays code-side. Null = configure the flow from props directly.
  final String? workflowId;

  /// KYB only: the mapped applicant workflow's id
  /// (`business.applicant.workflowId`, resolved server-side). Set by the
  /// workflow gate after overlaying its capture template; stamped on the
  /// applicant's own submission so the server applies that workflow's gates,
  /// pricing and decision graph. Internal — never set this yourself.
  final String? applicantWorkflowId;

  /// Dev-only base-URL override. Only applied for **development** keys
  /// (`pk_dev_…`); ignored for sandbox/production. Defaults to a platform-aware
  /// localhost (`http://10.0.2.2:3001` on Android emulators,
  /// `http://localhost:3001` elsewhere).
  final String? devUrl;

  /// Multi-region offering. When more than one entry is present the SDK inserts
  /// a country-select step and the picked entry's `idTypes` apply. Normally set
  /// by a resolved workflow; null/single-entry behaves like a single-country
  /// flow. The picked country becomes the effective country for the rest of the
  /// flow.
  final List<WorkflowCountryOption>? countries;

  /// Multi-ID policy: several ID checks in one run, judged by a pass policy.
  /// KYC only — publish rejects it on a KYB workflow.
  final MultiIdConfig? multiId;

  /// Subset of ID-type keys to offer (e.g. `['bvn', 'passport']`). Empty or
  /// null means "offer everything the org is granted". Intersected with the
  /// server's granted list.
  final List<String>? idTypes;
  final bool enableSelfie;
  final bool enableDocumentCapture;

  /// Allow picking a document photo from the device gallery as an alternative
  /// to the live camera capture. Default `true`. When `false`, the
  /// "upload a photo instead" affordances are hidden and the user must capture
  /// with the camera.
  final bool allowDocumentUpload;

  final bool enableLiveness;

  /// Presence Intelligence liveness method: `'gestures'` (default, randomized
  /// head-gesture challenges), `'flash'` (screen-reflection), or `'both'`.
  /// Affects billing (flash is priced lower than gestures; `both` charges both).
  /// Normally set by a resolved workflow. Sent on the verify body.
  final String livenessMode;

  /// Flash-liveness sequence length — how many colours the screen-reflection
  /// challenge uses (for `livenessMode` `'flash'`/`'both'`). More colours are
  /// harder to spoof but hold the user a little longer; clamped to the 5-colour
  /// palette. Default 4. Normally set by a resolved workflow.
  final int flashSequenceLength;

  /// Show a light/dark mode toggle button in the modal header. Default `true`.
  /// When `false`, the flow stays on the theme from [appearance] (its `theme`
  /// field) and the user can't switch it. Mirrors the web/RN SDKs'
  /// `showThemeToggle`.
  final bool showThemeToggle;

  /// How progress through the flow is drawn in the header.
  ///
  ///   • [MyazaProgressStyle.steps] (default) — numbered circles, one per step,
  ///     connected. Shows WHICH step you are on and how many there are, and
  ///     collapses to a window when they no longer fit.
  ///   • [MyazaProgressStyle.bar] — a single thin bar pinned to the header's
  ///     bottom edge. Quieter, and unaffected by step count, so it suits long
  ///     flows and hosts who would rather the chrome said less.
  ///   • [MyazaProgressStyle.none] — no progress in the header at all. For
  ///     hosts whose own surface already communicates progress, or short flows
  ///     where a step count is more noise than reassurance.
  ///
  /// [MyazaProgressStyle.steps] and [MyazaProgressStyle.bar] convey the same
  /// fraction; the choice is how much room it takes. [MyazaProgressStyle.none]
  /// opts out of conveying it here.
  /// Mirrors the RN SDK's `progressStyle`.
  final MyazaProgressStyle progressStyle;

  /// Hide the close (X) button and block all user-initiated dismissal — the X
  /// button, the Android back gesture, and (on iOS) the bottom-sheet swipe-down
  /// drag / barrier tap. When `true`, the flow can only be closed
  /// programmatically by popping the route the launcher returns (see
  /// [MyazaKYC.show], whose Future completes on close). Default `false`. The
  /// terminal "Submitted" step is already non-dismissible regardless.
  final bool disableClose;

  final MyazaKYCAppearance? appearance;

  /// Overrides for the consent (welcome) screen copy (title + description).
  final KYCConsentContent? consent;

  /// Overrides for the success (submitted) screen copy (title + description).
  final KYCSuccessContent? success;

  /// The org's own reference for the person being verified (e.g. your internal
  /// user id). It is NOT matched during verification — it becomes
  /// `Entity.externalUserId` at the KYC seam, so repeat checks of the same user
  /// collapse onto one entity and you can correlate results back to your record.
  /// Optional; when omitted the server falls back to the provider record id.
  final String? userId;

  /// Arbitrary, free-form metadata forwarded verbatim with every verification
  /// request. Nothing here is required or interpreted by the SDK/server — use
  /// [userId] for the user reference, not a `userId` key in here.
  final Map<String, dynamic>? metadata;
  final LivenessConfig? livenessConfig;

  /// Spoken liveness instructions (accessibility). TTS output only — no
  /// microphone is used. Default: enabled (`en-US`). Pass
  /// `VoiceGuidanceConfig.off` to mute, or `VoiceGuidanceConfig(language: …)`
  /// to pick a voice language.
  final VoiceGuidanceConfig voiceGuidance;

  /// Pre-fills form fields and personalises the welcome screen.
  final UserData? userData;

  /// Device Intelligence — device + IP fraud analysis (a soft signal server
  /// side). On by default. When `false`, the SDK skips fingerprint collection
  /// and the server skips the analysis + charge. Normally set by a workflow.
  final bool deviceIntelligence;

  /// KYB success screen: after submitting with key people still to verify,
  /// tapping Done offers the session's own web page so the applicant can
  /// reach the invite links again after the app closes. Default true;
  /// workflow opt-out `keyPeopleLinkRecovery: false`.
  final bool keyPeopleLinkRecovery;

  /// Show the consent (welcome) screen as the flow's first step. Default true.
  /// `false` is for a host app that has already collected the person's
  /// consent: the flow then opens straight on its first real step (the
  /// contact codes, the country picker, the ID list, the business form, or a
  /// scoped flow's own check). Normally set by a workflow (`consentStep`). It
  /// does not change what the organisation attests to the provider.
  final bool consentStep;

  /// The biometric scopes' flow options (workflow-driven, or passed here on a
  /// prop-configured mount): `selfieReview` shows the captured selfie with
  /// Retake and Continue before submitting (off by default on both biometric
  /// scopes); `resultDelivery` says where a re-authentication's verdict lands,
  /// 'both' (the default: the SDK holds the person on one loading screen until
  /// the check settles, and the org's webhook receives it too), 'app' (the
  /// same wait, but the server sends no webhook for the check) or 'webhook'
  /// (fire-and-forget); `doneButton` (default true) hides the final screen's
  /// Done when the host app closes the flow itself from `onResult`. A flow key
  /// wins per field. See config/biometric_options.dart.
  final BiometricFlowConfig? biometric;

  /// Extra-info / compliance questionnaire asked after capture, before
  /// submission. Null or empty = no questionnaire step. Normally set by a
  /// resolved workflow.
  final QuestionnaireConfig? questionnaire;

  /// Proof-of-address document collection (after capture). Null or disabled =
  /// no PoA step. Normally set by a resolved workflow.
  final ProofOfAddressConfig? proofOfAddress;

  /// Address Intelligence — smart-address capture (map pin + optional door
  /// photo and directions). Null or disabled = no step. On a KYB flow the pin
  /// is the business premises. Normally set by a resolved workflow.
  final AddressCollectionConfig? addressCollection;

  /// A reviewer sent this attempt back to redo specific steps.
  ///
  /// Never set by a consumer and never part of a published workflow — it is
  /// stamped onto ONE session's config snapshot when somebody clicks "Send
  /// back", so it arrives through the hosted bootstrap like any other session
  /// config. Null means the ordinary full flow.
  final ResubmitConfig? resubmit;

  /// Email OTP verification step (after consent). Null or disabled = no step.
  final EmailVerificationConfig? emailVerification;

  /// Phone OTP verification step (after consent, after email). Null or disabled
  /// = no step.
  final PhoneVerificationConfig? phoneVerification;

  /// eMRTD chip (NFC) verification for chip-capable IDs (after document
  /// capture). Null or disabled = no step. Normally set by a resolved workflow.
  final NfcConfig? nfc;

  /// What the flow verifies: `'individual'` (default) or `'business'` (KYB).
  /// Normally set by a resolved workflow — a live business flow requires a
  /// published KYB workflow. When `'business'`, [business] carries the registry
  /// config and the flow is consent → business-details → (questionnaire) →
  /// submitted (no capture/liveness).
  final String subjectType;

  /// Workflow scope — what this flow verifies (null = the full verification).
  /// Only ever set by a resolved workflow config / hosted session snapshot.
  final String? scope;

  /// KYB registry config — present when [subjectType] is `'business'`.
  final WorkflowBusinessConfig? business;

  const MyazaKYCConfig({
    required this.apiKey,
    this.country,
    this.workflowId,
    this.applicantWorkflowId,
    this.devUrl,
    this.countries,
    this.multiId,
    this.idTypes,
    this.enableSelfie = true,
    this.enableDocumentCapture = true,
    this.allowDocumentUpload = true,
    this.enableLiveness = true,
    this.livenessMode = 'gestures',
    this.flashSequenceLength = 4,
    this.showThemeToggle = true,
    this.progressStyle = MyazaProgressStyle.steps,
    this.disableClose = false,
    this.appearance,
    this.consent,
    this.success,
    this.userId,
    this.metadata,
    this.livenessConfig,
    this.voiceGuidance = const VoiceGuidanceConfig(),
    this.userData,
    this.deviceIntelligence = true,
    this.keyPeopleLinkRecovery = true,
    this.consentStep = true,
    this.biometric,
    this.questionnaire,
    this.resubmit,
    this.proofOfAddress,
    this.addressCollection,
    this.emailVerification,
    this.phoneVerification,
    this.nfc,
    this.subjectType = 'individual',
    this.scope,
    this.business,
  });

  /// Returns a copy with the given fields replaced. Used by the workflow merge
  /// to produce the effective config (flow-wins) before the flow mounts. Only
  /// the flow-controlled keys are exposed here; runtime data (apiKey, userId,
  /// userData, metadata) is never overridden by a workflow.
  MyazaKYCConfig copyWith({
    String? country,
    List<WorkflowCountryOption>? countries,
    MultiIdConfig? multiId,
    List<String>? idTypes,
    bool? enableSelfie,
    bool? enableDocumentCapture,
    bool? allowDocumentUpload,
    bool? enableLiveness,
    String? livenessMode,
    int? flashSequenceLength,
    bool? showThemeToggle,
    MyazaProgressStyle? progressStyle,
    bool? disableClose,
    MyazaKYCAppearance? appearance,
    KYCConsentContent? consent,
    KYCSuccessContent? success,
    VoiceGuidanceConfig? voiceGuidance,
    bool? deviceIntelligence,
    bool? keyPeopleLinkRecovery,
    bool? consentStep,
    BiometricFlowConfig? biometric,
    QuestionnaireConfig? questionnaire,
    ResubmitConfig? resubmit,
    ProofOfAddressConfig? proofOfAddress,
    AddressCollectionConfig? addressCollection,
    EmailVerificationConfig? emailVerification,
    PhoneVerificationConfig? phoneVerification,
    NfcConfig? nfc,
    String? subjectType,
    String? scope,
    WorkflowBusinessConfig? business,
    String? applicantWorkflowId,
  }) =>
      MyazaKYCConfig(
        apiKey: apiKey,
        country: country ?? this.country,
        workflowId: workflowId,
        applicantWorkflowId: applicantWorkflowId ?? this.applicantWorkflowId,
        devUrl: devUrl,
        countries: countries ?? this.countries,
        multiId: multiId ?? this.multiId,
        idTypes: idTypes ?? this.idTypes,
        enableSelfie: enableSelfie ?? this.enableSelfie,
        enableDocumentCapture:
            enableDocumentCapture ?? this.enableDocumentCapture,
        allowDocumentUpload: allowDocumentUpload ?? this.allowDocumentUpload,
        enableLiveness: enableLiveness ?? this.enableLiveness,
        livenessMode: livenessMode ?? this.livenessMode,
        flashSequenceLength: flashSequenceLength ?? this.flashSequenceLength,
        showThemeToggle: showThemeToggle ?? this.showThemeToggle,
        progressStyle: progressStyle ?? this.progressStyle,
        disableClose: disableClose ?? this.disableClose,
        appearance: appearance ?? this.appearance,
        consent: consent ?? this.consent,
        success: success ?? this.success,
        userId: userId,
        metadata: metadata,
        livenessConfig: livenessConfig,
        voiceGuidance: voiceGuidance ?? this.voiceGuidance,
        userData: userData,
        deviceIntelligence: deviceIntelligence ?? this.deviceIntelligence,
        keyPeopleLinkRecovery: keyPeopleLinkRecovery ?? this.keyPeopleLinkRecovery,
        consentStep: consentStep ?? this.consentStep,
        biometric: biometric ?? this.biometric,
        questionnaire: questionnaire ?? this.questionnaire,
        resubmit: resubmit ?? this.resubmit,
        proofOfAddress: proofOfAddress ?? this.proofOfAddress,
        addressCollection: addressCollection ?? this.addressCollection,
        emailVerification: emailVerification ?? this.emailVerification,
        phoneVerification: phoneVerification ?? this.phoneVerification,
        nfc: nfc ?? this.nfc,
        subjectType: subjectType ?? this.subjectType,
        scope: scope ?? this.scope,
        business: business ?? this.business,
      );
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
  /// Typed, documented error category. IDENTICAL to the web SDK's `KYCErrorCode`
  /// so integrators get one consistent contract across platforms. One of:
  ///   • 'network_error'            — connection failure / timeout (after retries)
  ///   • 'invalid_api_key'          — server returned 401
  ///   • 'insufficient_credits'     — server returned 402 (see [details])
  ///   • 'upload_failed'            — /api/kyc/upload failed (after retries)
  ///   • 'camera_permission_denied' — the user denied / the OS blocks camera access
  ///   • 'feature_disabled'         — server returned 403 (ID type / feature not enabled)
  ///   • 'invalid_workflow'         — the workflow is unknown, unpublished, or
  ///                                  can't be run by this SDK (KYB subject /
  ///                                  country / product mismatch)
  ///   • 'unknown'                  — anything else
  ///
  /// Voice guidance is text-to-speech *output* — it never records audio, so
  /// there is no microphone-permission code.
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
