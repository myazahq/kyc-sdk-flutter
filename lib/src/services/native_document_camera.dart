import 'dart:async';

import 'package:flutter/services.dart';

/// One analysed frame's text: the recognized lines, plus the normalised (0..1)
/// box they occupy when the platform could report it. The box is the only
/// geometry ML Kit offers — it has no rectangle detector — and stands in for
/// "how much of the frame the document's print covers".
class RecognizedFrame {
  final List<String> lines;
  final Rect? bounds;

  const RecognizedFrame(this.lines, this.bounds);

  static const empty = RecognizedFrame(<String>[], null);
}

/// Dart client for the **Android-native** document camera (CameraX).
///
/// On Android the Flutter camera plugin has to run Preview + ImageAnalysis +
/// VideoCapture together on the document step, which exceeds the CameraX
/// use-case cap on many devices: stream resolutions get downgraded (a soft
/// preview), every still tears the recording down and reconfigures the surface
/// (stutter, and a sideways flash to hide), and the plugin's preview widget
/// re-rotates itself off the accelerometer. This camera instead runs ONE native
/// session — Preview + ImageAnalysis + ImageCapture — with the side clip encoded
/// off the analysis frames, exactly as [NativeLivenessRecorder] does for
/// liveness.
///
/// The native side renders the preview into a Flutter texture; show [textureId]
/// with `NativeCameraPreview`. Recognized text lines arrive via the [start]
/// callback and drive the Dart-side auto-capture gate — every framing and MRZ
/// decision stays in Dart.
///
/// iOS does NOT use this — its plugin preview is stable and rotation-correct.
class NativeDocumentCamera {
  static const MethodChannel _method =
      MethodChannel('kyc_sdk_flutter/document_camera');
  static const EventChannel _textEvents =
      EventChannel('kyc_sdk_flutter/document_camera/text');

  int? _textureId;
  StreamSubscription<dynamic>? _textSub;

  /// The Flutter texture id for the camera preview (valid after [start]).
  int? get textureId => _textureId;

  /// Sensor rotation (degrees). Reported for diagnostics — the preview texture
  /// already arrives upright, so nothing rotates it.
  int rotationDegrees = 0;

  /// Preview buffer size in the sensor's native (landscape) orientation.
  int previewWidth = 0;
  int previewHeight = 0;

  /// Starts the camera + preview + analysis. Returns the preview texture id.
  /// [onText] receives each analysed frame's recognized text (empty when
  /// nothing was read).
  Future<int> start({required void Function(RecognizedFrame) onText}) async {
    final info = await _method.invokeMapMethod<String, dynamic>('start');
    final id = (info?['textureId'] as num?)?.toInt() ?? -1;
    _textureId = id;
    rotationDegrees = (info?['rotation'] as num?)?.toInt() ?? 0;
    previewWidth = (info?['previewWidth'] as num?)?.toInt() ?? 0;
    previewHeight = (info?['previewHeight'] as num?)?.toInt() ?? 0;

    _textSub = _textEvents.receiveBroadcastStream().listen(
      (event) => onText(event is Map ? _parseFrame(event) : RecognizedFrame.empty),
      onError: (_) => onText(RecognizedFrame.empty),
    );

    return id;
  }

  /// Begins recording the clip for the side being captured. Cheap — it touches
  /// no camera state, so switching sides or retaking never restarts the session.
  Future<void> startRecording() => _method.invokeMethod<void>('startRecording');

  /// Stops recording; returns the recorded MP4 path, or null.
  Future<String?> stopRecording() =>
      _method.invokeMethod<String>('stopRecording');

  /// Whether the device has a flash unit to use as a torch.
  Future<bool> hasTorch() async =>
      await _method.invokeMethod<bool>('hasTorch') ?? false;

  /// Switches the torch on/off.
  Future<void> setTorch(bool enabled) =>
      _method.invokeMethod<void>('setTorch', {'enabled': enabled});

  /// Takes the OCR-grade still, returned upright (the rotation is baked into
  /// the pixels natively, so there is no EXIF for the crop to misread).
  /// Returns null if the capture failed — the caller lets the user retake.
  Future<Uint8List?> captureStill({int quality = 95}) =>
      _method.invokeMethod<Uint8List>('captureStill', {'quality': quality});

  RecognizedFrame _parseFrame(Map<dynamic, dynamic> m) {
    final lines = (m['lines'] as List?)?.whereType<String>().toList(
              growable: false,
            ) ??
        const <String>[];
    final b = m['bounds'];
    Rect? bounds;
    if (b is List && b.length == 4) {
      final v = b.map((e) => (e as num).toDouble()).toList(growable: false);
      bounds = Rect.fromLTRB(v[0], v[1], v[2], v[3]);
    }
    return RecognizedFrame(lines, bounds);
  }

  /// Tears down the camera + analysis + texture.
  Future<void> dispose() async {
    await _textSub?.cancel();
    _textSub = null;
    try {
      await _method.invokeMethod<void>('dispose');
    } catch (_) {
      // best-effort
    }
    _textureId = null;
  }
}
