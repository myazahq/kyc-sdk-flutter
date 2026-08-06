import 'dart:async';

import 'package:flutter/services.dart';

import 'face_detection.dart';

/// Dart client for the **Android-native** liveness recorder (CameraX).
///
/// On Android, running the Flutter camera plugin's ImageAnalysis + VideoCapture
/// together exceeds the CameraX use-case cap and starves gesture detection. This
/// recorder instead drives a single native CameraX `ImageAnalysis` stream that is
/// fanned to BOTH ML Kit (face signals) AND a MediaCodec encoder (a clip that
/// shows the gestures) — so detection works *and* the video shows the gestures.
///
/// The native side renders the camera preview into a Flutter texture; [textureId]
/// is shown with a `Texture` widget. Face signals arrive via [faces].
///
/// iOS and the document/selfie steps do NOT use this — it's Android-liveness only.
class NativeLivenessRecorder {
  static const MethodChannel _method =
      MethodChannel('kyc_sdk_flutter/liveness_recorder');
  static const EventChannel _faceEvents =
      EventChannel('kyc_sdk_flutter/liveness_recorder/faces');

  int? _textureId;
  StreamSubscription<dynamic>? _faceSub;

  /// The Flutter texture id for the camera preview (valid after [start]).
  int? get textureId => _textureId;

  /// Sensor rotation (degrees) needed to make the preview upright.
  int rotationDegrees = 0;

  /// Preview buffer size in the sensor's native (landscape) orientation.
  int previewWidth = 0;
  int previewHeight = 0;

  /// Starts the camera + preview + analysis. Returns the preview texture id.
  /// [onFace] receives a [LivenessFaceData] per analysed frame, or null when no
  /// face is present.
  Future<int> start({required void Function(LivenessFaceData?) onFace}) async {
    final info = await _method.invokeMapMethod<String, dynamic>('startRecorder');
    final id = (info?['textureId'] as num?)?.toInt() ?? -1;
    _textureId = id;
    rotationDegrees = (info?['rotation'] as num?)?.toInt() ?? 0;
    previewWidth = (info?['previewWidth'] as num?)?.toInt() ?? 0;
    previewHeight = (info?['previewHeight'] as num?)?.toInt() ?? 0;

    _faceSub = _faceEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          onFace(_parse(event));
        } else {
          onFace(null);
        }
      },
      onError: (_) => onFace(null),
    );

    return id;
  }

  /// Begins recording the gesture clip.
  Future<void> startRecording() =>
      _method.invokeMethod<void>('startRecording');

  /// Stops recording; returns the recorded MP4 path, or null.
  Future<String?> stopRecording() =>
      _method.invokeMethod<String>('stopRecording');

  /// Encodes the latest camera frame to a front-facing JPEG (rotated upright +
  /// mirrored). Returns the bytes, or null if no frame is available yet.
  Future<Uint8List?> captureStill({int quality = 90}) =>
      _method.invokeMethod<Uint8List>('captureStill', {'quality': quality});

  /// Tears down the camera + analysis + texture.
  Future<void> dispose() async {
    await _faceSub?.cancel();
    _faceSub = null;
    try {
      await _method.invokeMethod<void>('disposeRecorder');
    } catch (_) {
      // best-effort
    }
    _textureId = null;
  }

  LivenessFaceData? _parse(Map<dynamic, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0.0;
    final faceCountRaw = m['faceCount'];
    // The native side only emits a map when a face was found.
    return LivenessFaceData(
      headEulerAngleX: d('headEulerAngleX'),
      headEulerAngleY: d('headEulerAngleY'),
      headEulerAngleZ: d('headEulerAngleZ'),
      smilingProbability: d('smilingProbability'),
      leftEyeOpenProbability: d('leftEyeOpenProbability'),
      rightEyeOpenProbability: d('rightEyeOpenProbability'),
      faceSizeRatio: d('faceSizeRatio'),
      faceCount: faceCountRaw is num ? faceCountRaw.toInt() : 1,
      faceCenterX: (m['faceCenterX'] as num?)?.toDouble(),
      faceCenterY: (m['faceCenterY'] as num?)?.toDouble(),
      trackingId: (m['trackingId'] as num?)?.toInt(),
      brightness: m['brightness'] is num ? (m['brightness'] as num).toDouble() : -1,
      faceRgb: (m['rgb'] as List?)?.map((v) => (v as num).toDouble()).toList(),
    );
  }
}
