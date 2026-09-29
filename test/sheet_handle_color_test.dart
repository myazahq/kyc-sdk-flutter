import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';

// The sheet grab handle must be visible. On dark themes it was drawn in
// #302D53, about 1.4:1 against the dark sheet surfaces, and all but vanished.

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('dark handle reaches 3:1 on every surface a handle sits on', () {
    const colors = MyazaColorScheme.dark;
    final handle = myazaHandleColor(colors, light: colors.gray300);
    final surfaces = {
      'background': colors.background,
      'backgroundSecondary': colors.backgroundSecondary,
      'header tint': kycHeaderSurface(colors, isDark: true),
    };
    for (final entry in surfaces.entries) {
      final seen = Color.alphaBlend(handle, entry.value);
      expect(_contrast(seen, entry.value), greaterThanOrEqualTo(3.0), reason: entry.key);
    }
  });

  test('a branded dark palette gets a visible handle too', () {
    final colors = MyazaColorScheme.dark.copyWith(
      background: const Color(0xFF12241A),
      backgroundSecondary: const Color(0xFF1B3326),
      textDark: const Color(0xFFE8F5EC),
    );
    final handle = myazaHandleColor(colors, light: colors.gray300);
    final seen = Color.alphaBlend(handle, colors.backgroundSecondary);
    expect(_contrast(seen, colors.backgroundSecondary), greaterThanOrEqualTo(3.0));
  });

  test('light themes keep the colour the caller used', () {
    const colors = MyazaColorScheme.light;
    expect(myazaHandleColor(colors, light: colors.gray300), colors.gray300);
    expect(myazaHandleColor(colors, light: colors.border), colors.border);
  });
}
