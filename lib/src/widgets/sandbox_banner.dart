import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

/// "You are not in production" strip, shown above the sheet's header.
///
/// A sandbox flow is pixel-identical to a live one, which is the point (you are
/// testing the real thing) and also the hazard: screenshots get mistaken for
/// production incidents, testers wonder why a real passport was rejected, and a
/// `pk_test_` key shipped to production looks like it works right up until
/// nobody is actually verified.
///
/// Environment comes from the SERVER (`/api/kyc/config`), not the API key
/// prefix. Hosted sessions authenticate with an `hs_` handoff token that
/// carries no environment slot, so key-sniffing would leave exactly the surface
/// an end user sees unlabelled.
///
/// DEVELOPMENT is labelled too, and differently: it runs the real pipeline
/// against staging provider credentials, so "test data only" would be a lie
/// there. 1:1 with the web and React Native SDKs.
class SandboxBanner extends StatelessWidget {
  /// Server-reported environment, or null while config is still loading.
  ///
  /// Passed in rather than read from Riverpod: the sheet that hosts this is a
  /// plain StatelessWidget, and making the banner a ConsumerWidget forced a
  /// ProviderScope on every host — which broke widget tests that mount the
  /// sheet on its own. A banner should not dictate its host's architecture.
  final String? environment;

  const SandboxBanner({super.key, required this.environment});

  // Fixed rather than themed: the strip must read identically in light and
  // dark, and it deliberately does not belong to the org's palette.
  //
  // `tint` is public because the full-screen host paints the status-bar strip
  // with it, so the amber runs from the very top of the screen through the
  // banner as ONE band (matching the React Native SDK) rather than starting
  // below the clock. It is translucent, so it composites over the same
  // background there as it does here.
  static const tint = Color(0x2EF59E0B);
  static const _ink = Color(0xFFB45309);

  /// Whether the banner renders for this environment. The full-screen host uses
  /// it to decide the status-bar strip colour, so the two cannot disagree about
  /// whether there is a band to continue.
  static bool showsFor(String? environment) =>
      environment == 'SANDBOX' || environment == 'DEVELOPMENT';

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (!showsFor(env)) {
      return const SizedBox.shrink();
    }

    final sandbox = env == 'SANDBOX';
    final text = context.myazaText;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: tint,
        padding: const EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: MyazaSpacing.xs + 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const MyazaIcon(MyazaIcons.flaskConical, size: 13, color: _ink),
            const SizedBox(width: MyazaSpacing.xs),
            Text(
              sandbox ? 'SANDBOX' : 'DEVELOPMENT',
              style: text.bodySmall.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _ink,
              ),
            ),
            const SizedBox(width: MyazaSpacing.xs),
            Flexible(
              child: Text(
                sandbox
                    ? 'Test data only, no real checks run'
                    : 'Test environment, results are not live',
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall.copyWith(fontSize: 11, color: _ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
