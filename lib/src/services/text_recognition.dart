import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

// ─── Native text recognition ──────────────────────────────────────────────────
//
// Thin bridge to the on-device recognizer — Apple Vision on iOS, ML Kit on
// Android — used by the MRZ scanner. Mirrors NativeFaceDetectorService: one
// camera frame per call, planes forwarded verbatim so each platform reads the
// format it expects (iOS BGRA, Android NV21).
//
// Returns an empty list when the platform has no implementation, so callers
// degrade to "found nothing" rather than crashing.

class TextRecognitionService {
  static const MethodChannel _channel =
      MethodChannel('kyc_sdk_flutter/text_recognition');

  bool _busy = false;

  /// True while a frame is in flight. The scanner uses this to drop frames
  /// instead of queueing them — recognition is far slower than the camera, and
  /// a backlog would make the preview lag badly.
  bool get isBusy => _busy;

  /// Recognizes an encoded still (JPEG/PNG) rather than a camera frame. Used
  /// to read the MRZ off the document photo the user already captured, so the
  /// chip step needs no second camera pass.
  Future<List<String>> recognizeBytes(Uint8List bytes) async {
    if (!Platform.isIOS && !Platform.isAndroid) return const [];
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('recognizeBytes', {'bytes': bytes});
      final lines = result?['lines'];
      if (lines is List) {
        return lines.whereType<String>().toList(growable: false);
      }
      return const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<String>> recognize(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) return const [];
    if (image.planes.isEmpty || _busy) return const [];

    _busy = true;
    try {
      final planes = image.planes
          .map((p) => <String, dynamic>{
                'bytes': p.bytes,
                'bytesPerRow': p.bytesPerRow,
                'bytesPerPixel': p.bytesPerPixel,
              })
          .toList(growable: false);

      final result =
          await _channel.invokeMapMethod<String, dynamic>('recognize', {
        'width': image.width,
        'height': image.height,
        'sensorOrientation': sensorOrientation,
        'planes': planes,
      });

      final lines = result?['lines'];
      if (lines is List) {
        return lines.whereType<String>().toList(growable: false);
      }
      return const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    } finally {
      _busy = false;
    }
  }
}
