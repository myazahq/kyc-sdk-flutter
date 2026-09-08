import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../config/theme.dart';

/// Vendor attribution, pinned to the bottom of the sheet on every screen.
///
/// "POWERED BY", deliberately, not "Secured by". At the moment this is on screen
/// the user is handing a passport and a live selfie to a company they have never
/// heard of, on behalf of one they have. What they need is PROVENANCE — a name
/// to hold responsible — not a promise. "Secured by" is an unfalsifiable claim
/// made at the exact moment we are collecting rather than protecting, it reads
/// like the reassurance a phishing screen writes, and it is a security assertion
/// a regulator can hold us to. Attribution is more credible precisely because it
/// claims nothing.
///
/// The lockup mirrors the dashboard's canonical treatment: [Myaza wordmark],
/// hairline rule, TRUST in tracked uppercase. The divider is a 1px CONTAINER,
/// not a "|" character — a typed pipe sits on the text baseline at whatever
/// weight the font gives it and reads as a separator between two names. The rule
/// is what makes it one brand: Myaza Trust.
///
/// The wordmark ships as a PNG rather than the brand SVG because Flutter cannot
/// parse SVG path data without `flutter_svg`, and a native plugin is a cost
/// every integrator would carry forever for one footer mark. The icon keeps its
/// brand colours in both themes; only the lettering flips, hence two assets.
///
/// Tappable, like the web and React Native SDKs. It was not, while
/// `url_launcher` was a dependency this SDK did not carry — that changed when
/// the consent screen needed real links (consent is only informed if the terms
/// can be opened), so the plugin is here anyway and the mark may as well lead
/// somewhere.
///
/// This widget OWNS the bottom safe-area inset for the whole sheet: the body's
/// scroll padding and the fill-mode screens each used to add
/// `MediaQuery.padding.bottom` themselves, which would now double up. Exactly
/// one thing clears the home indicator, and it is this.
class PoweredBy extends StatelessWidget {
  const PoweredBy({super.key});

  /// Rendered height of the wordmark. The asset is 648×200, so it is downscaled
  /// with headroom on every density; `cacheHeight` bounds the decode.
  static const double _markHeight = 24;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // ONE Myaza tone for the whole mark — label, wordmark, rule and TRUST —
    // picked against the background it actually sits on rather than taken from
    // the org's palette, so a customer's brand can never repaint our mark or
    // swallow it.
    final markColor = brandMarkColor(colors.background);
    // Derived from the SDK's OWN background, not `Theme.of(context).brightness`
    // — that reads the HOST app's ThemeData, which does not flip when the SDK's
    // theme toggle does, so the wordmark stayed light-on-light in dark mode.
    //
    // Luminance rather than the sheet's `isDark` flag on purpose: it is also
    // right when an org sets a dark custom `backgroundColor` while the theme is
    // nominally light. The lettering flips exactly when the surface behind it
    // does, which is the only thing that actually determines legibility.
    // The wordmark ships as a PNG, so its lettering colour cannot be tinted —
    // the ASSET is the choice. Pick the variant whose lettering matches the tone
    // the rest of the mark uses, or the logo would disagree with the text beside
    // it. Keyed off markColor rather than the background so the two can never
    // diverge.
    final isDark = markColor.computeLuminance() > 0.5;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: 10,
        // The RN sheet's rule, measurement for measurement (user decision
        // 2026-09-08: the two footers must sit the same distance off the
        // bottom edge). RN pads 12 on the iOS page sheet, whose bottom edge
        // already reaches the screen, and 12 plus the navigation-bar inset on
        // Android's edge-to-edge modal. Here the Android page is wrapped in a
        // SafeArea that has consumed that inset already, so the padding read
        // back is 0 and the two land on the same gap; on iOS the inset is
        // ignored exactly as RN ignores it, where `max(12, inset)` used to hold
        // the mark 34px up and the footer read as a heavy band beside RN's.
        bottom: 12 + (defaultTargetPlatform == TargetPlatform.iOS
            ? 0
            : MediaQuery.paddingOf(context).bottom),
      ),
      child: Opacity(
        opacity: 0.9,
        // A failed launch is swallowed: the provenance mark is the point, and a
        // device with no browser has nothing useful to show instead.
        // The ROW is not the link — only the mark is. A Row expands to its
        // constraints, so wrapping it in the GestureDetector made the entire
        // footer width open myaza.co. "Powered by" is a label, not a
        // destination.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Small and muted on purpose — "Powered by" is connective tissue,
            // not the message. The BRAND carries the weight.
            Text(
              'Powered by',
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: markColor,
              ),
            ),
            // Wider than the gaps INSIDE the lockup, so the mark reads as one
            // unit rather than three evenly-spaced items.
            const SizedBox(width: 10),
            // This is the link: wordmark, rule and TRUST are one brand, so the
            // whole lockup is the target — but nothing beyond it is.
            // A failed launch is swallowed: the provenance mark is the point,
            // and a device with no browser has nothing useful to show instead.
            GestureDetector(
              onTap: () async {
                try {
                  await launchUrl(Uri.parse(kProductUrl),
                      mode: LaunchMode.externalApplication);
                } catch (_) {
                  // no-op
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    isDark ? kWordmarkAssetDark : kWordmarkAssetLight,
                    package: kPackageName,
                    height: _markHeight,
                    // 3× the largest sensible render — keeps the decode small without
                    // visible softening on a 3x screen.
                    cacheHeight: (_markHeight * 3).round(),
                    fit: BoxFit.contain,
                    // A missing asset must never take the sheet down; the rest of the
                    // lockup still reads as attribution on its own.
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Container(
                      width: 1,
                      height: 20,
                      color: markColor.withValues(alpha: 0.35)),
                  const SizedBox(width: 8),
                  Text(
                    'TRUST',
                    // ~half the wordmark's height — the ratio the dashboard's own
                    // lockup uses. Level with the logo, TRUST competes with it.
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.68,
                      color: markColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
