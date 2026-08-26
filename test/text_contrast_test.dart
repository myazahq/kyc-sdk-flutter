import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';

// Every text colour must be readable on the surface it sits on.
//
// This is not a style preference, it is WCAG 1.4.3 (AA, 4.5:1 for body text),
// and it regressed silently: `textMuted` shipped at 3.79:1 on white and 2.97:1
// on the default dark, dropping to 2.45:1 on the dark greens orgs brand with.
// A colour is legible or it is not; nothing about reading the palette says
// which, so it is measured.

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const schemes = {
    'light': MyazaColorScheme.light,
    'dark': MyazaColorScheme.dark,
  };

  group('body text clears WCAG AA on its own background', () {
    for (final entry in schemes.entries) {
      final scheme = entry.value;
      for (final text in {
        'textDark': scheme.textDark,
        'textSecondary': scheme.textSecondary,
        'textMuted': scheme.textMuted,
      }.entries) {
        test('${entry.key}: ${text.key}', () {
          final ratio = contrast(text.value, scheme.background);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '${text.key} is ${ratio.toStringAsFixed(2)}:1 on the '
                  '${entry.key} background');
        });
      }
    }
  });

  test('a branded dark background does not sink the muted tier', () {
    // Orgs set their own dark background, and a green one is dimmer than the
    // default #040218. The tier that failed did so worst exactly here.
    const branded = Color(0xFF0D2114);
    expect(contrast(MyazaColorScheme.dark.textMuted, branded),
        greaterThanOrEqualTo(4.5));
    expect(contrast(MyazaColorScheme.dark.textSecondary, branded),
        greaterThanOrEqualTo(4.5));
  });
}
