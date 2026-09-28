import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── KYC theme mode provider ──────────────────────────────────────────────────
//
// Scoped to each KYC ProviderScope override — users can toggle light/dark
// independently of the host app.
// Default: ThemeMode.system (follows device setting).

final kycThemeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.system,
);

// ─── Liveness camera on ───────────────────────────────────────────────────────
//
// Set by the liveness screen from the moment its camera screen shows until the
// step is left (the selfie review after it included; the ready and permission
// primers before it excluded). The flow reads it to render in the light theme
// and hold the screen bright; see config/bright_screen.dart. Scoped per flow
// by kycFlowOverrides.

final livenessCameraOnProvider = StateProvider<bool>((ref) => false);
