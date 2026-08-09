import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vendor brand constants for the SDK's own attribution — NOT the integrating
/// org's branding (that comes from `/api/kyc/config`).
///
/// The platform is **Myaza Trust**, a product of **Myaza** (the parent company).
/// Always the full product name: bare "Myaza" is the company, and a pipe
/// ("Myaza | Trust") reads as a separator between two items rather than one
/// name. See the naming rule in kyc-dashboard/CLAUDE.md.
const String kProductName = 'Myaza Trust';

/// The product site — where "who are these people?" gets answered.
const String kProductUrl = 'https://trust.myaza.co';

/// Package name — required by `Image.asset(..., package:)` so the wordmark
/// resolves from THIS package's bundle rather than the host app's.
const String kPackageName = 'myaza_kyc_sdk_flutter';

/// Wordmark assets. The icon keeps its brand colours in both themes; only the
/// "myaza" lettering flips, so there are two files rather than a tint.
const String kWordmarkAssetLight = 'assets/brand/myaza-wordmark-light.png';
const String kWordmarkAssetDark = 'assets/brand/myaza-wordmark-dark.png';

/// End-user legal documents referenced by the consent screen. These are MYAZA's
/// terms — the person consents to us processing their data as the verification
/// provider — so they are never org-overridable.
///
/// Tappable on the consent screen, via `url_launcher`. The plugin is a real
/// cost to every integrator, taken deliberately: consent given by tapping
/// Continue is only INFORMED if the documents it references can be opened, and
/// a printed address the user must retype is a poor substitute for that.
const String kTermsUrl = 'https://trust.myaza.co/legal/terms';
const String kPrivacyUrl = 'https://trust.myaza.co/legal/privacy';

/// Version of the consent wording. Consent is given by ACTING (tapping
/// Continue) rather than ticking a box, so bump this whenever the copy changes
/// materially and store it with the verification — otherwise nothing proves
/// which disclosure was on screen. Keep in step with the web SDK's value.
const String kConsentVersion = '2026-08-06.1';

/// Tones the footer mark may use — the design system's INK and LIGHT text
/// colours, not the brand purple.
///
/// Attribution, not advertising. A saturated purple mark is the loudest thing in
/// the footer on an org whose palette is yellow or green: it draws the eye to
/// the least important element on screen and reads as a clash rather than a
/// signature. Every comparable vendor mark is monochrome for the same reason.
///
/// Nothing is lost by it — the wordmark ASSET keeps its brand fills, so the
/// Myaza identity is still carried by the logo while the text recedes.
///
/// Mirrors the web and React Native SDKs — keep the list and the rule in step.
const List<Color> _markTones = [
  Color(0xFF070330),
  Color(0xFFF6F5FE),
];

/// WCAG AA for the small text this renders at.
const double _minMarkContrast = 4.5;

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The mark tone that stays legible on [background].
///
/// The footer mark must NOT follow the org's palette: it is our attribution, and
/// an org whose brand sits close to ours would otherwise get a mark that either
/// stops reading as Myaza or vanishes into the background. Chosen by CONTRAST
/// rather than by light/dark, because an org can set any background — including
/// mid-tones where neither variant is obviously right.
///
/// Falls back to the most visible tone when none clears AA, so the answer is
/// always the best available rather than a fixed guess.
Color brandMarkColor(Color background) {
  for (final tone in _markTones) {
    if (_contrastRatio(tone, background) >= _minMarkContrast) return tone;
  }
  return _markTones.reduce(
    (best, tone) => _contrastRatio(tone, background) > _contrastRatio(best, background)
        ? tone
        : best,
  );
}
