import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';

/// A brand import produces TWO palettes: the light one lands on the appearance
/// and the dark one in `appearance.dark`.
///
/// The appearance is applied on top of whichever base scheme is active, so
/// without the dark block an org's LIGHT background simply overwrote the dark
/// one — a branded flow kept light surfaces after the theme toggle, which made
/// dark mode useless for every customer who set colours.
void main() {
  const light = MyazaKYCAppearance(
    primaryColor: Color(0xFF5645F5),
    backgroundColor: Color(0xFFFCF7F2),
    textColor: Color(0xFF231D2D),
    dark: MyazaKYCAppearance(
      primaryColor: Color(0xFF7B6EF7),
      backgroundColor: Color(0xFF110C1A),
      textColor: Color(0xFFF4F2FA),
    ),
  );

  group('forBrightness', () {
    test('returns the light palette unchanged in light mode', () {
      final a = light.forBrightness(false);
      expect(a.backgroundColor, const Color(0xFFFCF7F2));
      expect(a.textColor, const Color(0xFF231D2D));
    });

    test('folds in the DARK overrides in dark mode', () {
      // THE BUG: this returned the light background before.
      final a = light.forBrightness(true);
      expect(a.backgroundColor, const Color(0xFF110C1A));
      expect(a.textColor, const Color(0xFFF4F2FA));
      expect(a.primaryColor, const Color(0xFF7B6EF7));
    });

    test('merges partially — a dark block may set only some tokens', () {
      const partial = MyazaKYCAppearance(
        primaryColor: Color(0xFF5645F5),
        backgroundColor: Color(0xFFFFFFFF),
        dark: MyazaKYCAppearance(backgroundColor: Color(0xFF000000)),
      );
      final a = partial.forBrightness(true);
      expect(a.backgroundColor, const Color(0xFF000000));
      // Untouched by the dark block, so the light value still applies rather
      // than disappearing.
      expect(a.primaryColor, const Color(0xFF5645F5));
    });

    test('is a no-op when no dark block was given', () {
      const only = MyazaKYCAppearance(backgroundColor: Color(0xFFFFFFFF));
      expect(only.forBrightness(true).backgroundColor, const Color(0xFFFFFFFF));
    });

    test('carries non-colour settings through unchanged', () {
      // Radius and fonts never differ by mode; dropping them on the dark path
      // would silently un-brand half the flow.
      const a = MyazaKYCAppearance(
        borderRadius: 4,
        fontFamily: 'Poppins',
        dark: MyazaKYCAppearance(backgroundColor: Color(0xFF000000)),
      );
      final d = a.forBrightness(true);
      expect(d.borderRadius, 4);
      expect(d.fontFamily, 'Poppins');
    });
  });
}
