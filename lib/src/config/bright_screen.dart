import 'package:flutter/widgets.dart';

import 'appearance_scheme.dart';
import 'kyc_config.dart';
import 'theme.dart';

// ─── Bright screen during liveness ────────────────────────────────────────────
//
// While the selfie camera is on, the phone's screen is the light on the
// person's face. A dark theme at low brightness leaves the face in shadow, so
// from the camera screen to the end of the liveness step the flow switches to
// the organisation's LIGHT palette and raises this app's screen brightness to
// full, and puts both back when the step is left. The ready and permission
// primers before the camera keep the normal theme and brightness.
// Mirrors the web and React Native SDKs.
//
// These are the pure decisions; the brightness call itself lives in
// liveness/screen_brightness.dart and the lifecycle wiring in
// widgets/bright_screen_boost.dart.

/// How long the theme takes to cross into (or back out of) the light palette.
const Duration kBrightScreenTransition = Duration(milliseconds: 300);

/// Whether the flow should be lit right now: the workflow allows it (absent
/// means on), the liveness step is showing and it has reached its camera
/// screen ([cameraOn] is the step's latch, see [livenessStepLit]).
bool livenessBrightScreenActive({
  required bool enabled,
  required bool onLivenessStep,
  required bool cameraOn,
}) =>
    enabled && onLivenessStep && cameraOn;

/// Whether the liveness screen's selfie camera is running: started, past the
/// ready and permission screens with the face model ready, and no selfie taken
/// yet (a stored selfie opens on review, a completed one hands over). A denied
/// camera shows its own screen, so it counts as off.
bool livenessCameraRunning({
  required bool started,
  required bool pastPrimers,
  required bool faceModelReady,
  required bool permissionDenied,
  required bool selfieTaken,
}) =>
    started && pastPrimers && faceModelReady && !permissionDenied && !selfieTaken;

/// Whether the liveness step is lit now. Nothing is lit on the ready screen or
/// the camera-permission primer: those keep the organisation's own theme and
/// the person's brightness. The step lights up when the camera screen does,
/// and stays lit for the rest of the step (the selfie review after it, a
/// retake) so the theme does not flip back and forth under the person. The
/// latch is dropped only by leaving the step.
bool livenessStepLit({
  required bool alreadyLit,
  required bool cameraRunning,
}) =>
    alreadyLit || cameraRunning;

/// Whether the screen brightness should be held at full: lit AND the app is
/// in the foreground. A backgrounded app gives the screen back to the person.
/// A null lifecycle state (not yet reported) counts as foreground.
bool brightScreenBoostWanted({
  required bool active,
  AppLifecycleState? lifecycle,
}) {
  if (!active) return false;
  return switch (lifecycle) {
    AppLifecycleState.paused ||
    AppLifecycleState.hidden ||
    AppLifecycleState.detached =>
      false,
    // `inactive` covers the control centre, a notification shade and the
    // permission prompt: the app is still on screen, so the light stays.
    _ => true,
  };
}

/// The transition to use: none when the person has asked the system for
/// reduced motion.
Duration brightScreenTransition({required bool disableAnimations}) =>
    disableAnimations ? Duration.zero : kBrightScreenTransition;

/// The palette the lit screen paints with: the organisation's BASE (light)
/// appearance over the light scheme. Dark overrides never apply here.
MyazaColorScheme brightScreenScheme(MyazaKYCAppearance? appearance) =>
    applyAppearance(MyazaColorScheme.light, appearance);

/// The theme a frame paints with, [t] of the way from the person's own theme
/// to the lit one (0 = theirs, 1 = fully lit). Colours blend; the dark/light
/// flag (status-bar icons, the header's tint rule) flips at the midpoint.
({MyazaColorScheme scheme, bool isDark, Color headerSurface}) blendBrightScreen({
  required MyazaColorScheme userScheme,
  required bool userIsDark,
  required MyazaColorScheme litScheme,
  required double t,
}) {
  final clamped = t.clamp(0.0, 1.0);
  if (clamped == 0) {
    return (
      scheme: userScheme,
      isDark: userIsDark,
      headerSurface: kycHeaderSurface(userScheme, isDark: userIsDark),
    );
  }
  final scheme = userScheme.lerp(litScheme, clamped);
  final header = Color.lerp(
    kycHeaderSurface(userScheme, isDark: userIsDark),
    kycHeaderSurface(litScheme, isDark: false),
    clamped,
  )!;
  return (scheme: scheme, isDark: userIsDark && clamped < 0.5, headerSurface: header);
}
