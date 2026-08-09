import '../config/contact_verification.dart';
import '../config/kyc_config.dart';

// ─── Contact verification — resolved per-channel settings ─────────────────────
//
// The contact step is one widget mounted twice ('email' | 'phone'), so every
// option has to be read from a different config block per channel. Resolving
// that once here keeps the screen free of `isPhone ? … : …` ladders (and its
// file inside the 200-line limit).

/// Server-side minimum code length (the server clamps codeLength to 4–8).
const int kMinCodeLength = 4;

final _emailRe = RegExp(r'.+@.+\..+');

/// Deliberately permissive: the real proof of an address is that a code sent to
/// it arrives, and a stricter pattern only rejects addresses that would work.
bool isPlausibleContactEmail(String value) => _emailRe.hasMatch(value);

class ContactChannelSettings {
  final bool isPhone;
  final int codeLength;
  final OtpInputStyle inputStyle;
  final bool required;

  /// Phone only — the delivery channels on offer. Empty for email. When it
  /// holds more than one the step shows a picker; the user's choice wins.
  final List<String> offeredChannels;

  final int? maxAttempts;

  /// Seed country for the phone field; falls back to the flow's country.
  final String defaultCountry;

  const ContactChannelSettings({
    required this.isPhone,
    required this.codeLength,
    required this.inputStyle,
    required this.required,
    required this.offeredChannels,
    required this.maxAttempts,
    required this.defaultCountry,
  });

  /// The channel used until the user picks otherwise. Null for email.
  String? get defaultChannel =>
      offeredChannels.isEmpty ? null : offeredChannels.first;

  /// The offered channel that is NOT [picked], or null when only one is on
  /// offer. Drives the "send by X instead" escape hatch on the code panel.
  String? otherThan(String? picked) {
    final current = picked ?? defaultChannel;
    for (final c in offeredChannels) {
      if (c != current) return c;
    }
    return null;
  }

  /// Reads the block matching [channel] off [config], applying the same
  /// defaults the server clamps to (6 digits, segmented, required).
  factory ContactChannelSettings.resolve(
    MyazaKYCConfig config,
    String channel,
  ) {
    final isPhone = channel == 'phone';
    final email = config.emailVerification;
    final phone = config.phoneVerification;

    return ContactChannelSettings(
      isPhone: isPhone,
      codeLength: isPhone ? (phone?.codeLength ?? 6) : (email?.codeLength ?? 6),
      inputStyle: isPhone
          ? (phone?.inputStyle ?? OtpInputStyle.segmented)
          : (email?.inputStyle ?? OtpInputStyle.segmented),
      required: isPhone ? (phone?.required ?? true) : (email?.required ?? true),
      offeredChannels:
          isPhone ? (phone?.offeredChannels ?? const ['sms']) : const [],
      maxAttempts: isPhone ? phone?.maxAttempts : email?.maxAttempts,
      defaultCountry: phone?.defaultCountry ?? config.country ?? '',
    );
  }
}
