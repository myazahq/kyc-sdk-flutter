import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Theme-aware color scheme (ThemeExtension) ───────────────────────────────
//
// Inject via Theme.of(context).extensions.
// Access via context.myazaColors (extension below).

class MyazaColorScheme extends ThemeExtension<MyazaColorScheme> {
  final Color background;
  final Color backgroundSecondary;
  final Color textDark;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color primary;
  /// Text/icon color rendered on top of [primary] (e.g. button labels).
  final Color onPrimary;
  final Color primary50;
  final Color primary100;
  final Color primary200;
  final Color gray300;
  final Color gray400;
  final Color successBg;
  final Color errorBg;
  final Color warningBg;
  final Color infoBg;

  const MyazaColorScheme({
    required this.background,
    required this.backgroundSecondary,
    required this.textDark,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.primary50,
    required this.primary100,
    required this.primary200,
    required this.gray300,
    required this.gray400,
    required this.successBg,
    required this.errorBg,
    required this.warningBg,
    required this.infoBg,
  });

  // ── Light ──────────────────────────────────────────────────────────────────

  static const MyazaColorScheme light = MyazaColorScheme(
    background:          Color(0xFFFFFFFF),
    backgroundSecondary: Color(0xFFF6F5FE),
    textDark:            Color(0xFF070330),
    textSecondary:       Color(0xFF5A5775),
    textMuted:           Color(0xFF828197),
    border:              Color(0xFFD3CFFC),
    primary:             Color(0xFF5645F5),
    onPrimary:           Color(0xFFFFFFFF),
    primary50:           Color(0xFFF6F5FE),
    primary100:          Color(0xFFE9E7FE),
    primary200:          Color(0xFFD3CFFC),
    gray300:             Color(0xFFCDCDD6),
    gray400:             Color(0xFFACABBA),
    successBg:           Color(0xFFD8F4DC),
    errorBg:             Color(0xFFFCD8D8),
    warningBg:           Color(0xFFFFF1D6),
    infoBg:              Color(0xFFC8E9FF),
  );

  // ── Dark ───────────────────────────────────────────────────────────────────

  static const MyazaColorScheme dark = MyazaColorScheme(
    background:          Color(0xFF040218),
    backgroundSecondary: Color(0xFF0F0C2E),
    textDark:            Color(0xFFF6F5FE),
    textSecondary:       Color(0xFFACABBA),
    textMuted:           Color(0xFF5A5775),
    border:              Color(0xFF302D53),
    primary:             Color(0xFF7B6EF7),
    onPrimary:           Color(0xFFFFFFFF),
    primary50:           Color(0xFF1A1730),
    primary100:          Color(0xFF2A2651),
    primary200:          Color(0xFF3D3870),
    gray300:             Color(0xFF302D53),
    gray400:             Color(0xFF5A5775),
    successBg:           Color(0xFF0B2B0C),
    errorBg:             Color(0xFF2B0A0A),
    warningBg:           Color(0xFF2B1B00),
    infoBg:              Color(0xFF001B3B),
  );

  // ── ThemeExtension impl ────────────────────────────────────────────────────

  @override
  MyazaColorScheme copyWith({
    Color? background,
    Color? backgroundSecondary,
    Color? textDark,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? primary,
    Color? onPrimary,
    Color? primary50,
    Color? primary100,
    Color? primary200,
    Color? gray300,
    Color? gray400,
    Color? successBg,
    Color? errorBg,
    Color? warningBg,
    Color? infoBg,
  }) => MyazaColorScheme(
    background:          background          ?? this.background,
    backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
    textDark:            textDark            ?? this.textDark,
    textSecondary:       textSecondary       ?? this.textSecondary,
    textMuted:           textMuted           ?? this.textMuted,
    border:              border              ?? this.border,
    primary:             primary             ?? this.primary,
    onPrimary:           onPrimary           ?? this.onPrimary,
    primary50:           primary50           ?? this.primary50,
    primary100:          primary100          ?? this.primary100,
    primary200:          primary200          ?? this.primary200,
    gray300:             gray300             ?? this.gray300,
    gray400:             gray400             ?? this.gray400,
    successBg:           successBg           ?? this.successBg,
    errorBg:             errorBg             ?? this.errorBg,
    warningBg:           warningBg           ?? this.warningBg,
    infoBg:              infoBg              ?? this.infoBg,
  );

  @override
  MyazaColorScheme lerp(MyazaColorScheme? other, double t) {
    if (other == null) return this;
    return MyazaColorScheme(
      background:          Color.lerp(background,          other.background,          t)!,
      backgroundSecondary: Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      textDark:            Color.lerp(textDark,            other.textDark,            t)!,
      textSecondary:       Color.lerp(textSecondary,       other.textSecondary,       t)!,
      textMuted:           Color.lerp(textMuted,           other.textMuted,           t)!,
      border:              Color.lerp(border,              other.border,              t)!,
      primary:             Color.lerp(primary,             other.primary,             t)!,
      onPrimary:           Color.lerp(onPrimary,           other.onPrimary,           t)!,
      primary50:           Color.lerp(primary50,           other.primary50,           t)!,
      primary100:          Color.lerp(primary100,          other.primary100,          t)!,
      primary200:          Color.lerp(primary200,          other.primary200,          t)!,
      gray300:             Color.lerp(gray300,             other.gray300,             t)!,
      gray400:             Color.lerp(gray400,             other.gray400,             t)!,
      successBg:           Color.lerp(successBg,           other.successBg,           t)!,
      errorBg:             Color.lerp(errorBg,             other.errorBg,             t)!,
      warningBg:           Color.lerp(warningBg,           other.warningBg,           t)!,
      infoBg:              Color.lerp(infoBg,              other.infoBg,              t)!,
    );
  }
}

// ─── Header surface tint ──────────────────────────────────────────────────────

/// Surface tint for the KYC header chrome (brand + title + step indicator).
///
/// Dark themes get a branded lift over [MyazaColorScheme.background] for clear
/// contrast with the body; light themes use the subtle secondary surface. Used
/// by both the sheet header block and the full-screen Scaffold (status-bar area)
/// so they stay in sync.
Color kycHeaderSurface(MyazaColorScheme colors, {required bool isDark}) => isDark
    ? Color.alphaBlend(
        colors.primary.withValues(alpha: 0.18),
        colors.background,
      )
    : colors.backgroundSecondary;

// ─── BuildContext extensions ──────────────────────────────────────────────────

extension MyazaBuildContextTheme on BuildContext {
  /// Returns the current Myaza color scheme (light or dark).
  MyazaColorScheme get myazaColors =>
      Theme.of(this).extension<MyazaColorScheme>() ?? MyazaColorScheme.light;

  /// Returns typography styles tinted with the current theme colors.
  MyazaThemeText get myazaText => MyazaThemeText(myazaColors);
}

// ─── Theme-aware text styles ──────────────────────────────────────────────────

class MyazaThemeText {
  final MyazaColorScheme _colors;

  const MyazaThemeText(this._colors);

  TextStyle get heading1 => GoogleFonts.spaceGrotesk(
    fontSize: 24, fontWeight: FontWeight.w700, color: _colors.textDark,
  );

  TextStyle get heading2 => GoogleFonts.spaceGrotesk(
    fontSize: 20, fontWeight: FontWeight.w600, color: _colors.textDark,
  );

  TextStyle get heading3 => GoogleFonts.spaceGrotesk(
    fontSize: 16, fontWeight: FontWeight.w600, color: _colors.textDark,
  );

  TextStyle get body => GoogleFonts.karla(
    fontSize: 16, fontWeight: FontWeight.w400, color: _colors.textDark,
  );

  TextStyle get bodyMedium => GoogleFonts.karla(
    fontSize: 14, fontWeight: FontWeight.w400, color: _colors.textSecondary,
  );

  TextStyle get bodySmall => GoogleFonts.karla(
    fontSize: 12, fontWeight: FontWeight.w400, color: _colors.textMuted,
  );

  TextStyle get button => GoogleFonts.karla(
    fontSize: 16, fontWeight: FontWeight.w600, color: _colors.onPrimary,
  );

  TextStyle get label => GoogleFonts.karla(
    fontSize: 14, fontWeight: FontWeight.w500, color: _colors.textDark,
  );
}

// ─── Colors ───────────────────────────────────────────────────────────────────

class MyazaColors {
  MyazaColors._();

  // Primary — Myaza Purple
  static const Color primary = Color(0xFF5645F5); // PC-09 Main
  static const Color primaryDark = Color(0xFF1F156F);
  static const Color primary50 = Color(0xFFF6F5FE);
  static const Color primary100 = Color(0xFFE9E7FE);
  static const Color primary200 = Color(0xFFD3CFFC);
  static const Color primary300 = Color(0xFFBDB6FB);
  static const Color primary400 = Color(0xFFA6B8FA);
  static const Color primary500 = Color(0xFF9986F9);
  static const Color primary600 = Color(0xFF7B6EF7);
  static const Color primary700 = Color(0xFF6455F6);
  static const Color primary800 = Color(0xFF5B47F5);
  static const Color primary900 = Color(0xFF3A25F4);
  static const Color primary950 = Color(0xFF2400F2);

  // Secondary — Gold
  static const Color secondary = Color(0xFFF4B746); // SC-06 Main
  static const Color secondary50 = Color(0xFFFDF1DA);
  static const Color secondary100 = Color(0xFFFBE7C1);
  static const Color secondary200 = Color(0xFFFADBA2);
  static const Color secondary500 = Color(0xFFF4B746);
  static const Color secondary900 = Color(0xFF513D17);

  // Text
  static const Color textDark = Color(0xFF070330);
  static const Color textLight = Color(0xFFF6F5FE);
  static const Color textSecondary = Color(0xFF5A5775);
  static const Color textMuted = Color(0xFF828197);

  // Status
  static const Color success = Color(0xFF0DA211);
  static const Color successBg = Color(0xFFD8F4DC);
  static const Color error = Color(0xFFBD1B09);
  static const Color errorBg = Color(0xFFFCD8D8);
  static const Color warning = Color(0xFFFFC107);
  static const Color warningBg = Color(0xFFFFF1D6);
  static const Color info = Color(0xFF004FAF);
  static const Color infoBg = Color(0xFFC8E9FF);

  // Grays
  static const Color gray50 = Color(0xFFF6F5FE);
  static const Color gray100 = Color(0xFFE9E7FE);
  static const Color gray200 = Color(0xFFD3CFFC);
  static const Color gray300 = Color(0xFFCDCDD6);
  static const Color gray400 = Color(0xFFACABBA);
  static const Color gray500 = Color(0xFF828197);
  static const Color gray600 = Color(0xFF5A5775);
  static const Color gray700 = Color(0xFF302D53);
  static const Color gray800 = Color(0xFF070330);

  // Borders
  static const Color border = Color(0xFFD3CFFC);

  // Background
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundSecondary = Color(0xFFF6F5FE);
}

// ─── Typography ───────────────────────────────────────────────────────────────

class MyazaTypography {
  MyazaTypography._();

  static TextStyle heading1 = GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: MyazaColors.textDark,
  );

  static TextStyle heading2 = GoogleFonts.spaceGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: MyazaColors.textDark,
  );

  static TextStyle heading3 = GoogleFonts.spaceGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: MyazaColors.textDark,
  );

  static TextStyle body = GoogleFonts.karla(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: MyazaColors.textDark,
  );

  static TextStyle bodyMedium = GoogleFonts.karla(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: MyazaColors.textSecondary,
  );

  static TextStyle bodySmall = GoogleFonts.karla(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MyazaColors.textMuted,
  );

  static TextStyle button = GoogleFonts.karla(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static TextStyle label = GoogleFonts.karla(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MyazaColors.textDark,
  );
}

// ─── Radius ───────────────────────────────────────────────────────────────────

class MyazaRadius {
  MyazaRadius._();

  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double full = 999.0;
}

// ─── Spacing ─────────────────────────────────────────────────────────────────

class MyazaSpacing {
  MyazaSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

// ─── Sizing ──────────────────────────────────────────────────────────────────

class MyazaSizing {
  MyazaSizing._();

  static const double buttonHeight = 48.0;
  static const double inputHeight = 48.0;
  static const double iconSize = 24.0;
  static const double avatarSize = 80.0;
  static const double cameraCircleSize = 260.0;
}
