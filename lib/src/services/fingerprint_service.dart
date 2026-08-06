import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// ─── Device fingerprint ───────────────────────────────────────────────────────
//
// Collects a lightweight device fingerprint for the Device Intelligence layer.
// Rides the verify payload at `metadata.device.fingerprint = { deviceId,
// components }` — only when `deviceIntelligence` is on. The server canonicalizes
// + SHA-256-hashes the raw components (deviceHash); the SDK just sends them.
// A fingerprint is a RISK SIGNAL, never an identity link (models collide).

class FingerprintService {
  FingerprintService._();
  static final FingerprintService instance = FingerprintService._();

  static const _uuid = Uuid();
  static const _fileName = 'myaza_kyc_did';

  String? _cachedDeviceId;
  Map<String, dynamic>? _cached;

  /// Returns `{ deviceId, components }`. Best-effort — never throws; returns a
  /// partial map (or components-only) if the persistent id can't be read.
  Future<Map<String, dynamic>> collect() async {
    if (_cached != null) return _cached!;
    final deviceId = await _persistentDeviceId();
    final result = <String, dynamic>{
      if (deviceId != null) 'deviceId': deviceId,
      'components': _components(),
    };
    _cached = result;
    return result;
  }

  Map<String, dynamic> _components() {
    final view = PlatformDispatcher.instance.implicitView;
    final size = view?.physicalSize;
    final dpr = view?.devicePixelRatio ?? 1.0;
    final now = DateTime.now();
    return {
      if (size != null) 'screen': {
          'width': size.width.round(),
          'height': size.height.round(),
          'pixelRatio': dpr,
        },
      'timezone': now.timeZoneName,
      'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
      'languages': PlatformDispatcher.instance.locales
          .take(5)
          .map((l) => l.toLanguageTag())
          .toList(growable: false),
      'hardwareConcurrency': Platform.numberOfProcessors,
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
    };
  }

  /// A per-install UUID persisted to the app support dir (the mobile analog of
  /// the web SDK's localStorage `myaza-kyc-did`). Generated once, then reused.
  Future<String?> _persistentDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return _cachedDeviceId = existing;
      }
      final id = _uuid.v4();
      await file.writeAsString(id, flush: true);
      return _cachedDeviceId = id;
    } catch (_) {
      return null; // best-effort — components still ride without a deviceId
    }
  }
}
