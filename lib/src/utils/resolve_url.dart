import 'dart:io' show Platform;

import '../config/kyc_config.dart';

// ─── Automatic environment detection from the API key prefix ──────────────────
//
// The environment is encoded in the key prefix — the single source of truth
// (there is no manual environment option). The prefix carries scope
// (`pk` publishable / `sk` secret) and environment (`dev`/`test`/`live`); we
// read ONLY the environment portion, so detection works for both key types.
// Mirrors the server's KEY_PREFIXES (kyc-core/src/lib/api-keys.ts):
//
//   pk_dev_…  / sk_dev_…   → development
//   pk_test_… / sk_test_…  → sandbox
//   pk_live_… / sk_live_…  → production

/// Canonical base URLs for the non-development environments
/// (see the kyc-dashboard environments docs).
const _baseUrls = <KYCEnvironment, String>{
  // Sandbox and production share the same host; the key prefix selects the env.
  KYCEnvironment.sandbox: 'https://trust.myaza.app',
  KYCEnvironment.production: 'https://trust.myaza.app',
};

/// Default base URL for development keys when no [devUrl] is provided.
///
/// Android emulators reach the host machine via `10.0.2.2`; everywhere else
/// (iOS simulator, desktop) `localhost` works directly.
String get _defaultDevUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3001' : 'http://localhost:3001';

// Matches the environment slot of a Myaza API key prefix, regardless of the
// pk_/sk_ scope: pk_dev_ / sk_dev_ / pk_test_ / sk_test_ / pk_live_ / sk_live_.
final RegExp _keyEnvRe = RegExp(r'^(?:pk|sk)_(dev|test|live)_');

/// Derives the environment from the API key prefix. Throws [ArgumentError] on an
/// unrecognized / malformed key — never silently defaults (defaulting to
/// production would be dangerous).
KYCEnvironment detectEnvironment(String apiKey) {
  final match = _keyEnvRe.firstMatch(apiKey);
  switch (match?.group(1)) {
    case 'dev':
      return KYCEnvironment.development;
    case 'test':
      return KYCEnvironment.sandbox;
    case 'live':
      return KYCEnvironment.production;
    default:
      throw ArgumentError(
        'Invalid Myaza API key: expected a dev, test, or live key prefix '
        '(e.g. pk_dev_…, pk_test_…, or pk_live_…).',
      );
  }
}

/// Resolves the API base URL from the [apiKey]. The environment is detected from
/// the key prefix:
///
/// - development → [devUrl] if provided, otherwise a platform-aware localhost.
/// - sandbox / production → the hardcoded URL ([devUrl] is ignored).
///
/// Throws on an invalid key (via [detectEnvironment]).
String resolveBaseUrl(String apiKey, {String? devUrl}) {
  final environment = detectEnvironment(apiKey);
  if (environment == KYCEnvironment.development) {
    return devUrl ?? _defaultDevUrl;
  }
  return _baseUrls[environment]!;
}

/// Rewrites a server-served absolute URL (e.g. the branding logo) so its HOST
/// matches the base URL the SDK actually talks to.
///
/// The server builds absolute logo/media URLs from its own `PUBLIC_SERVER_URL`,
/// which can differ from the host the SDK reaches it on — a dev USB tunnel
/// (`adb reverse` → localhost), a LAN IP vs an mDNS `.local` name, etc. The logo
/// is served by the SAME server (`/api/kyc/branding/logo/…`), so rebasing its
/// path onto [baseUrl] makes it load. In production the two hosts already match,
/// so this is a no-op. Returns the input unchanged if either URL is unparseable.
String? rebaseServerUrl(String? url, String baseUrl) {
  if (url == null || url.isEmpty) return url;
  try {
    final u = Uri.parse(url);
    final base = Uri.parse(baseUrl);
    return base
        .replace(path: u.path, query: u.hasQuery ? u.query : null)
        .toString();
  } catch (_) {
    return url;
  }
}

/// The path every image the server serves for branding lives under: the org
/// logo, a workflow's own logo and the custom footer logos alike.
const String _serverBrandingPath = '/api/kyc/branding/';

bool _isServerBrandingUrl(Object? url) =>
    url is String && (Uri.tryParse(url)?.path.startsWith(_serverBrandingPath) ?? false);

Map<String, dynamic>? _asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

Map<String, dynamic> _rebaseKey(
  Map<String, dynamic> block,
  String key,
  String baseUrl,
) =>
    _isServerBrandingUrl(block[key])
        ? {...block, key: rebaseServerUrl(block[key] as String, baseUrl)}
        : block;

/// A config or workflow response with every server-served branding image
/// rebased onto [baseUrl] (see [rebaseServerUrl]): `branding.logo`, the custom
/// footer's `branding.trustAttribution.logo` / `logoDark`, and the workflow's
/// own `config.appearance.logo` (and its dark theme's). Only the server's own
/// branding URLs move; a consumer's literal image URL is left alone. Without
/// this a dev USB tunnel (`adb reverse` → localhost) loaded the org logo but
/// not a workflow's logo or the footer logos, whose host is the server's
/// PUBLIC_SERVER_URL. A no-op in production, where the two hosts match.
Map<String, dynamic> rebaseServerAssets(
  Map<String, dynamic> json,
  String baseUrl,
) {
  var out = json;
  final branding = _asMap(json['branding']);
  if (branding != null) {
    var b = _rebaseKey(branding, 'logo', baseUrl);
    final attribution = _asMap(b['trustAttribution']);
    if (attribution != null) {
      final a = _rebaseKey(_rebaseKey(attribution, 'logo', baseUrl), 'logoDark', baseUrl);
      b = {...b, 'trustAttribution': a};
    }
    out = {...out, 'branding': b};
  }
  final config = _asMap(json['config']);
  final appearance = _asMap(config?['appearance']);
  if (config != null && appearance != null) {
    var a = _rebaseKey(appearance, 'logo', baseUrl);
    final dark = _asMap(a['dark']);
    if (dark != null) a = {...a, 'dark': _rebaseKey(dark, 'logo', baseUrl)};
    out = {...out, 'config': {...config, 'appearance': a}};
  }
  return out;
}
