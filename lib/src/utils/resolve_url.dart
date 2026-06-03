import 'dart:io' show Platform;

import '../config/kyc_config.dart';

/// Hardcoded base URLs for the non-development environments.
const _baseUrls = <KYCEnvironment, String>{
  KYCEnvironment.staging: 'https://identity.myaza.app',
  KYCEnvironment.production: 'https://identity.myaza.app',
};

/// Default base URL used in development when no [devUrl] is provided.
///
/// Android emulators reach the host machine via `10.0.2.2`; everywhere else
/// (iOS simulator, desktop) `localhost` works directly.
String get _defaultDevUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3001' : 'http://localhost:3001';

/// Resolves the API base URL for the given [environment].
///
/// - [KYCEnvironment.development] → [devUrl] if provided, otherwise a
///   platform-aware localhost default.
/// - [KYCEnvironment.staging] / [KYCEnvironment.production] → the hardcoded
///   URL ([devUrl] is ignored).
String resolveBaseUrl(KYCEnvironment environment, {String? devUrl}) {
  if (environment == KYCEnvironment.development) {
    return devUrl ?? _defaultDevUrl;
  }
  return _baseUrls[environment]!;
}
