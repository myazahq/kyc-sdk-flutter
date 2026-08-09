import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/brand.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';

/// The footer mark resolves its contrast against the background it will
/// ACTUALLY sit on. On the web that was got wrong: an imported palette puts the
/// LIGHT background on the base tokens and the dark one in `appearance.dark`,
/// so resolving against the base value on a dark flow picked the ink tone and
/// painted near-black text onto a near-black surface.
///
/// These pin that Flutter resolves the same way — through the palette for the
/// active brightness, not the raw appearance.
void main() {
  const imported = MyazaKYCAppearance(
    backgroundColor: Color(0xFFFCF7F2), // light palette
    dark: MyazaKYCAppearance(backgroundColor: Color(0xFF1A0F00)), // dark palette
  );

  test('a dark flow resolves against the DARK background', () {
    final a = imported.forBrightness(true);
    expect(a.backgroundColor, const Color(0xFF1A0F00));
    // Near-black surface must take the LIGHT mark.
    expect(brandMarkColor(a.backgroundColor!), const Color(0xFFF6F5FE));
  });

  test('a light flow resolves against the light background', () {
    final a = imported.forBrightness(false);
    expect(a.backgroundColor, const Color(0xFFFCF7F2));
    expect(brandMarkColor(a.backgroundColor!), const Color(0xFF070330));
  });

  test('the mark is always neutral, never a brand hue', () {
    // Attribution, not advertising — it must not clash with an org palette.
    const neutrals = [Color(0xFF070330), Color(0xFFF6F5FE)];
    for (final bg in [
      const Color(0xFFFFFFFF),
      const Color(0xFF040218),
      const Color(0xFF1A0F00),
      const Color(0xFFFFC107),
      const Color(0xFF5645F5),
    ]) {
      expect(neutrals, contains(brandMarkColor(bg)));
    }
  });

  test('the SDK default schemes still get a legible mark', () {
    expect(brandMarkColor(MyazaColorScheme.light.background), const Color(0xFF070330));
    expect(brandMarkColor(MyazaColorScheme.dark.background), const Color(0xFFF6F5FE));
  });
}
