// ─── Contact verification config ──────────────────────────────────────────────
//
// Optional email / phone OTP steps shown right after consent. The org authors
// these in the workflow builder; the SDK collects a destination, sends a code,
// and verifies it — the proof token rides the verify submission. Mirrors the
// web SDK's Email/PhoneVerificationConfig.

enum OtpInputStyle {
  segmented,
  text;

  static OtpInputStyle fromString(String? raw) =>
      raw == 'text' ? OtpInputStyle.text : OtpInputStyle.segmented;
}

int _clampCodeLength(Object? raw) {
  final n = (raw as num?)?.toInt() ?? 6;
  return n < 4 ? 4 : (n > 8 ? 8 : n);
}

class EmailVerificationConfig {
  final bool enabled;

  /// When false, the step offers a "skip for now" affordance. Default true.
  final bool required;

  /// OTP length (clamped 4–8, default 6).
  final int codeLength;

  /// Server-enforced attempt budget (default 3) — the client never counts.
  final int maxAttempts;
  final OtpInputStyle inputStyle;

  const EmailVerificationConfig({
    this.enabled = false,
    this.required = true,
    this.codeLength = 6,
    this.maxAttempts = 3,
    this.inputStyle = OtpInputStyle.segmented,
  });

  factory EmailVerificationConfig.fromJson(Map<String, dynamic> json) =>
      EmailVerificationConfig(
        enabled: json['enabled'] as bool? ?? false,
        required: json['required'] as bool? ?? true,
        codeLength: _clampCodeLength(json['codeLength']),
        maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
        inputStyle: OtpInputStyle.fromString(json['inputStyle'] as String?),
      );
}

class PhoneVerificationConfig {
  final bool enabled;
  final bool required;
  final int codeLength;
  final int maxAttempts;
  final OtpInputStyle inputStyle;

  /// Delivery channels on offer (`sms` / `whatsapp`). The org chooses what is
  /// offered; when there is more than one, the USER picks between them on the
  /// step — only they know whether they have WhatsApp installed.
  final List<String> channels;

  /// Default dial-code country (ISO-2); falls back to the flow's country.
  final String? defaultCountry;

  const PhoneVerificationConfig({
    this.enabled = false,
    this.required = true,
    this.codeLength = 6,
    this.maxAttempts = 3,
    this.inputStyle = OtpInputStyle.segmented,
    this.channels = const ['sms'],
    this.defaultCountry,
  });

  /// Offered channels, normalised — never empty, unknown values dropped.
  List<String> get offeredChannels {
    final known =
        channels.where((c) => c == 'sms' || c == 'whatsapp').toSet().toList();
    return known.isEmpty ? const ['sms'] : known;
  }

  /// The channel used until the user picks otherwise (first offered).
  String get via => offeredChannels.first;

  factory PhoneVerificationConfig.fromJson(Map<String, dynamic> json) =>
      PhoneVerificationConfig(
        enabled: json['enabled'] as bool? ?? false,
        required: json['required'] as bool? ?? true,
        codeLength: _clampCodeLength(json['codeLength']),
        maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 3,
        inputStyle: OtpInputStyle.fromString(json['inputStyle'] as String?),
        channels: ((json['channels'] as List?) ?? const ['sms'])
            .map((e) => e.toString())
            .toList(growable: false),
        defaultCountry: json['defaultCountry'] as String?,
      );
}
