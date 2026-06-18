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
  KYCEnvironment.sandbox: 'https://identity.myaza.app',
  KYCEnvironment.production: 'https://identity.myaza.app',
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
