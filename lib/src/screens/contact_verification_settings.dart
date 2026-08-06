import '../config/contact_verification.dart';
import '../config/kyc_config.dart';

// ─── Contact verification — resolved per-channel settings ─────────────────────
//
// The contact step is one widget mounted twice ('email' | 'phone'), so every
// option has to be read from a different config block per channel. Resolving
// that once here keeps the screen free of `isPhone ? … : …` ladders (and its
// file inside the 200-line limit).

class ContactChannelSettings {
  final bool isPhone;
  final int codeLength;
  final OtpInputStyle inputStyle;
  final bool required;

  /// Phone only — the delivery channel ('sms' | 'whatsapp'). Null for email.
  final String? via;

  final int? maxAttempts;

  /// Seed country for the phone field; falls back to the flow's country.
  final String defaultCountry;

  const ContactChannelSettings({
    required this.isPhone,
    required this.codeLength,
    required this.inputStyle,
    required this.required,
    required this.via,
    required this.maxAttempts,
    required this.defaultCountry,
  });

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
      codeLength:
          isPhone ? (phone?.codeLength ?? 6) : (email?.codeLength ?? 6),
      inputStyle: isPhone
          ? (phone?.inputStyle ?? OtpInputStyle.segmented)
          : (email?.inputStyle ?? OtpInputStyle.segmented),
      required: isPhone ? (phone?.required ?? true) : (email?.required ?? true),
      via: isPhone ? phone?.via : null,
      maxAttempts: isPhone ? phone?.maxAttempts : email?.maxAttempts,
      defaultCountry: phone?.defaultCountry ?? config.country ?? '',
    );
  }
}
