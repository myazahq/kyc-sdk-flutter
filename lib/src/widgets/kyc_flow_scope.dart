import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/theme_provider.dart';

// ─── The scope a flow mounts in ──────────────────────────────────────────────
//
// One override list, shared by every host that runs a step of the flow: the KYC
// flow itself and face re-authentication, which hosts the liveness step in its
// own scope.
//
// It lives in its OWN file rather than beside MyazaKYC because both hosts need
// it and the entry point needs to be able to mount either: with the list on
// MyazaKYC, the biometric host imported the KYC widget, so the KYC widget could
// not import the biometric host back without an import cycle (2026-09-16).

/// The theme mode a flow opens in, from the consumer's appearance.
ThemeMode initialThemeMode(MyazaKYCAppearance? a) => switch (a?.theme) {
      MyazaThemeMode.light => ThemeMode.light,
      MyazaThemeMode.dark => ThemeMode.dark,
      MyazaThemeMode.system || null => ThemeMode.system,
    };

/// The ProviderScope overrides a flow mounts with, optionally carrying the
/// server config a workflow resolution already fetched. One list, so a notifier
/// added here reaches every host.
List<Override> kycFlowOverrides(
  MyazaKYCConfig config,
  ServerSdkConfig? preloaded,
) =>
    [
      // Config must be first — the notifiers read it during build.
      kycConfigProvider.overrideWithValue(config),
      if (preloaded != null)
        preloadedServerConfigProvider.overrideWithValue(preloaded),
      // Scope all three KYC notifiers to this container so they read
      // kycConfigProvider from the override above, not from the root
      // ProviderScope (which has no override and would throw).
      kYCNotifierProvider.overrideWith(KYCNotifier.new),
      cameraNotifierProvider.overrideWith(CameraNotifier.new),
      livenessNotifierProvider.overrideWith(LivenessNotifier.new),
      kycThemeModeProvider.overrideWith((ref) => initialThemeMode(config.appearance)),
    ];
