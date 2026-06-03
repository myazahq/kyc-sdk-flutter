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
