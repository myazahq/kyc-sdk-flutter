import 'package:flutter/material.dart';

import 'kyc_config.dart';
import 'theme.dart';

// ─── Appearance → color scheme ────────────────────────────────────────────────
//
// Maps the consumer's MyazaKYCAppearance overrides onto the base (light/dark)
// MyazaColorScheme. Unset colors keep the built-in token. When a primaryColor
// is given, the primary tint family (50/100/200) is derived from it so the
// whole brand family follows; an explicit accentColor overrides the 100 tint.
//
// Shared: the flow itself themes every screen with this, and the workflow gate
// themes its resolve loader with it, so the loader shown BEFORE the flow opens
// is already in the caller's brand rather than the built-in purple.

MyazaColorScheme applyAppearance(
  MyazaColorScheme base,
  MyazaKYCAppearance? a,
) {
  if (a == null) return base;
  final primary = a.primaryColor ?? base.primary;
  final background = a.backgroundColor ?? base.background;
  final hasPrimary = a.primaryColor != null;
  Color tint(double opacity) =>
      Color.alphaBlend(primary.withValues(alpha: opacity), background);

  return base.copyWith(
    primary: primary,
    onPrimary: a.primaryTextColor,
    background: background,
    backgroundSecondary: a.surfaceColor,
    border: a.borderColor,
    textDark: a.textColor,
    primary50: hasPrimary ? tint(0.06) : null,
    primary100: a.accentColor ?? (hasPrimary ? tint(0.12) : null),
    primary200: hasPrimary ? tint(0.24) : null,
  );
}

/// The scheme to paint with for [appearance], resolving its theme mode against
/// the device brightness the same way the flow does.
MyazaColorScheme schemeForAppearance(
  MyazaKYCAppearance? appearance,
  ThemeMode mode, {
  required Brightness platformBrightness,
}) {
  final isDark = mode == ThemeMode.dark ||
      (mode == ThemeMode.system && platformBrightness == Brightness.dark);
  final base = isDark ? MyazaColorScheme.dark : MyazaColorScheme.light;
  return applyAppearance(base, appearance?.forBrightness(isDark));
}
