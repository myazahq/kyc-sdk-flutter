import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart' show kSdkVersion;

// Rich device & SDK metadata collected from the Flutter runtime at verify time.
// Sent as `metadata.device` in the verify payload — the server merges this
// with server-side facts (real IP, request user-agent, X-SDK-Version header)
// before persisting to Verification.deviceMetadata.

class DeviceMetadataService {
  DeviceMetadataService._();

  static final DeviceMetadataService instance = DeviceMetadataService._();

  Map<String, dynamic>? _cached;

  Future<Map<String, dynamic>> collect() async {
    if (_cached != null) return _cached!;

    final base = <String, dynamic>{
      'sdkType': 'flutter',
      'sdkVersion': kSdkVersion,
      'sdkPlatform': _platformName(),
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      base.addAll(await _collectAppInfo());
    } catch (_) {/* non-fatal */}

    try {
      base.addAll(await _collectDeviceInfo());
    } catch (_) {/* non-fatal */}

    try {
      base.addAll(_collectDisplayInfo());
    } catch (_) {/* non-fatal */}

    try {
      base.addAll(_collectLocaleInfo());
    } catch (_) {/* non-fatal */}

    _cached = base;
    return base;
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isFuchsia) return 'fuchsia';
    return 'unknown';
  }

  Future<Map<String, dynamic>> _collectAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    return {
      'app': {
        'name': info.appName,
        'package': info.packageName,
        'version': info.version,
        'buildNumber': info.buildNumber,
      },
    };
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final plugin = DeviceInfoPlugin();

    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      final ua = web.userAgent ?? '';
      return {
        'device': {
          'type': _inferDeviceType(ua),
          'vendor': web.vendor,
        },
        'os': {
          'name': web.platform ?? 'web',
        },
        'browser': {
          'name': web.browserName.name,
          'version': web.appVersion,
        },
        'userAgent': ua,
        'hardware': {
          'cores': web.hardwareConcurrency,
          'memoryGb': web.deviceMemory,
          'touchPoints': web.maxTouchPoints,
        },
      };
    }

    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      return {
        'device': {
          'type': _inferAndroidType(a),
          'vendor': a.brand,
          'manufacturer': a.manufacturer,
          'model': a.model,
          'product': a.product,
          'device': a.device,
          'hardware': a.hardware,
          'board': a.board,
          'isPhysicalDevice': a.isPhysicalDevice,
        },
        'os': {
          'name': 'Android',
          'version': a.version.release,
          'sdkInt': a.version.sdkInt,
          'codename': a.version.codename,
          'incremental': a.version.incremental,
          'securityPatch': a.version.securityPatch,
        },
        'hardware': {
          'supportedAbis': a.supportedAbis,
          'fingerprint': a.fingerprint,
        },
      };
    }

    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      return {
        'device': {
          'type': _inferIosType(i.model),
          'vendor': 'Apple',
          'model': i.model,
          'name': i.name,
          'localizedModel': i.localizedModel,
          'utsnameMachine': i.utsname.machine,
          'identifierForVendor': i.identifierForVendor,
          'isPhysicalDevice': i.isPhysicalDevice,
        },
        'os': {
          'name': i.systemName,
          'version': i.systemVersion,
        },
      };
    }

    if (Platform.isMacOS) {
      final m = await plugin.macOsInfo;
      return {
        'device': {
          'type': 'desktop',
          'vendor': 'Apple',
          'model': m.model,
          'name': m.computerName,
          'arch': m.arch,
          'cpuFrequency': m.cpuFrequency,
        },
        'os': {
          'name': 'macOS',
          'version': m.osRelease,
          'majorVersion': m.majorVersion,
          'minorVersion': m.minorVersion,
          'patchVersion': m.patchVersion,
        },
        'hardware': {
          'cores': m.activeCPUs,
          'memoryGb': m.memorySize > 0
              ? (m.memorySize / (1024 * 1024 * 1024)).round()
              : null,
        },
      };
    }

    if (Platform.isWindows) {
      final w = await plugin.windowsInfo;
      return {
        'device': {
          'type': 'desktop',
          'name': w.computerName,
        },
        'os': {
          'name': 'Windows',
          'version': w.displayVersion,
          'productName': w.productName,
          'releaseId': w.releaseId,
          'buildNumber': w.buildNumber,
        },
        'hardware': {
          'cores': w.numberOfCores,
        },
      };
    }

    if (Platform.isLinux) {
      final l = await plugin.linuxInfo;
      return {
        'device': {
          'type': 'desktop',
          'name': l.name,
        },
        'os': {
          'name': 'Linux',
          'version': l.version,
          'prettyName': l.prettyName,
          'id': l.id,
          'versionId': l.versionId,
        },
      };
    }

    return {};
  }

  Map<String, dynamic> _collectDisplayInfo() {
    // Use the platform dispatcher so this works without a BuildContext.
    final view = WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
        ? WidgetsBinding.instance.platformDispatcher.views.first
        : null;
    if (view == null) return {};
    final size = view.physicalSize;
    final dpr = view.devicePixelRatio;
    return {
      'screen': {
        'width': dpr > 0 ? (size.width / dpr).round() : size.width.round(),
        'height': dpr > 0 ? (size.height / dpr).round() : size.height.round(),
        'physicalWidth': size.width.round(),
        'physicalHeight': size.height.round(),
        'devicePixelRatio': dpr,
      },
    };
  }

  Map<String, dynamic> _collectLocaleInfo() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final locale = dispatcher.locale;
    final languages = dispatcher.locales.map((l) => l.toLanguageTag()).toList();
    final tzOffset = DateTime.now().timeZoneOffset;
    return {
      'locale': locale.toLanguageTag(),
      'language': locale.languageCode,
      'languages': languages,
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': tzOffset.inMinutes,
    };
  }

  // ── Device-type heuristics ──────────────────────────────────────────────

  String _inferIosType(String modelRaw) {
    final m = modelRaw.toLowerCase();
    if (m.contains('ipad')) return 'tablet';
    if (m.contains('iphone') || m.contains('ipod')) return 'mobile';
    return 'mobile';
  }

  String _inferAndroidType(AndroidDeviceInfo info) {
    // Heuristic: tablets typically have a `tablet` system feature flag, but
    // since we don't have direct access here, fall back to "mobile" for now.
    // Smallest-width >= 600 dp is the canonical tablet check, but device_info_plus
    // doesn't expose it — so the dashboard treats this field as best-effort.
    final hint = '${info.model} ${info.product} ${info.device}'.toLowerCase();
    if (hint.contains('tablet') || hint.contains('tab ')) return 'tablet';
    return 'mobile';
  }

  String _inferDeviceType(String userAgent) {
    final ua = userAgent.toLowerCase();
    if (ua.contains('ipad') || ua.contains('tablet')) return 'tablet';
    if (ua.contains('mobi') || ua.contains('iphone') || ua.contains('android')) {
      return 'mobile';
    }
    return 'desktop';
  }
}

