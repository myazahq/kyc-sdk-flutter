import 'dart:io' show Platform;
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

// ─── Face data value object ───────────────────────────────────────────────────
//
// A snapshot of the face attributes we care about from a single camera frame.
// All fields are non-nullable — a face detector returns null when any required
// attribute is missing from the detected face.
//
// This type (and the gesture-detection functions below) are intentionally free
// of any ML Kit dependency so the core SDK builds on every platform/architecture
// — including Apple-Silicon iOS simulators, where GoogleMLKit ships no arm64
// slice. The actual on-device detector lives behind [FaceDetectorService] and is
// provided by an optional companion package (e.g. myaza_kyc_sdk_flutter_mlkit).

class LivenessFaceData {
  /// Head pitch: positive = looking up, negative = looking down.
  /// Nod detection uses this axis (threshold: −10° → +5° recovery).
  final double headEulerAngleX;

  /// Head yaw: positive = turned left, negative = turned right.
  /// Turn detection uses this axis (threshold: ±25°).
  final double headEulerAngleY;

  /// Head roll / tilt (unused for gesture detection but available).
  final double headEulerAngleZ;

  /// 0.0 (not smiling) → 1.0 (smiling). Smile threshold: > 0.7.
  final double smilingProbability;

  /// 0.0 (closed) → 1.0 (open). Blink detection uses the average of both eyes.
  final double leftEyeOpenProbability;

  /// 0.0 (closed) → 1.0 (open).
  final double rightEyeOpenProbability;

  /// Normalized face width relative to the display frame (0.0–1.0).
  /// Mirrors the web SDK's faceWidth metric:
  ///   < 0.2  → too far   ("Kindly move closer")
  ///   > 0.7  → too close ("Kindly move further away")
  ///   0.2–0.7 → correct distance
  final double faceSizeRatio;

  /// Number of faces the native detector found in the frame. The gesture
  /// signals above describe the dominant (largest) face; the liveness flow uses
  /// `> 1` to pause challenges ("Make sure only your face is visible"). Defaults
  /// to 1 for detectors that don't report a count.
  final int faceCount;

  /// Mean frame luminance (0–255), or `< 0` when not provided. Supplied by the
  /// Android native recorder (which owns the camera, so the raw frame never
  /// reaches Dart) to drive lighting guidance. iOS computes brightness from the
  /// Flutter-camera frame directly, so it leaves this unset.
  final double brightness;

  /// Convenience: average of both eye-open probabilities.
  double get eyeAverageOpenProbability =>
      (leftEyeOpenProbability + rightEyeOpenProbability) / 2;

  const LivenessFaceData({
    required this.headEulerAngleX,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
    required this.smilingProbability,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    required this.faceSizeRatio,
    this.faceCount = 1,
    this.brightness = -1,
  });
}

// ─── Face detector service (interface) ────────────────────────────────────────
//
// Abstraction over a per-frame face detector. The core SDK depends only on this
// interface — never on a concrete ML library — so it stays buildable everywhere.
//
// Implementations:
//   • [NativeFaceDetectorService] — built-in, **default**. Real on-device
//     detection via the in-package native plugin: Apple Vision on iOS, Google
//     ML Kit (native Gradle) on Android. No cross-platform GoogleMLKit pod, so
//     the SDK still builds & runs on Apple-Silicon iOS simulators (where, having
//     no camera, it simply reports no faces).
//   • [StubFaceDetectorService] — no-op fallback. Used only if a host explicitly
//     registers it, or on a platform the native plugin doesn't cover.
//
// Hosts don't need to register anything — [createFaceDetectorService] returns the
// native detector by default. [registerFaceDetectorFactory] lets a host override
// it (e.g. a custom detector, or the stub for tests).
//
// Lifecycle: create via [createFaceDetectorService], call [initialize] before
// use, and [dispose] when the liveness screen exits.

abstract class FaceDetectorService {
  /// Prepares the detector for use. Must be called once before [detect].
  void initialize();

  /// Processes a single camera [image] and returns the dominant face's gesture
  /// data, or null when no usable face is present (or this is the stub).
  ///
  /// [sensorOrientation] is the camera sensor orientation in degrees (from the
  /// `CameraDescription`); implementations use it to rotate the frame correctly.
  Future<LivenessFaceData?> detect(
    CameraImage image, {
    required int sensorOrientation,
  });

  /// Releases any native resources. Safe to call multiple times.
  Future<void> dispose();
}

/// No-op detector. Always reports "no face", so liveness never advances on its
/// own — used as a fallback (e.g. unsupported platform, or explicitly in tests).
class StubFaceDetectorService implements FaceDetectorService {
  @override
  void initialize() {}

  @override
  Future<LivenessFaceData?> detect(
    CameraImage image, {
    required int sensorOrientation,
  }) async =>
      null;

  @override
  Future<void> dispose() async {}
}

/// The built-in, default detector. Dispatches each camera frame to the SDK's
/// in-package native plugin over a method channel and maps the result to
/// [LivenessFaceData]:
///   • iOS     → Apple Vision (`VNDetectFaceLandmarksRequest`)
///   • Android → Google ML Kit (native Gradle `com.google.mlkit:face-detection`)
///
/// Neither pulls the cross-platform GoogleMLKit CocoaPod, so the SDK builds on
/// Apple-Silicon iOS simulators. On platforms the plugin doesn't implement (or
/// when the channel is unavailable), [detect] returns null — the same graceful
/// "no face" behaviour as the stub.
class NativeFaceDetectorService implements FaceDetectorService {
  static const MethodChannel _channel =
      MethodChannel('kyc_sdk_flutter/face_detection');

  bool _disposed = false;

  @override
  void initialize() {
    _disposed = false;
  }

  @override
  Future<LivenessFaceData?> detect(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (_disposed) return null;
    if (!Platform.isIOS && !Platform.isAndroid) return null;
    if (image.planes.isEmpty) return null;

    // iOS delivers a single BGRA plane; Android delivers NV21. Send every
    // plane's bytes + strides so the native side reads its expected format.
    final planes = image.planes
        .map((p) => <String, dynamic>{
              'bytes': p.bytes,
              'bytesPerRow': p.bytesPerRow,
              'bytesPerPixel': p.bytesPerPixel,
            })
        .toList(growable: false);

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('detect', {
        'width': image.width,
        'height': image.height,
        'sensorOrientation': sensorOrientation,
        'planes': planes,
      });
      if (result == null) return null;

      double d(String k) => (result[k] as num).toDouble();
      final faceCountRaw = result['faceCount'];
      return LivenessFaceData(
        headEulerAngleX: d('headEulerAngleX'),
        headEulerAngleY: d('headEulerAngleY'),
        headEulerAngleZ: d('headEulerAngleZ'),
        smilingProbability: d('smilingProbability'),
        leftEyeOpenProbability: d('leftEyeOpenProbability'),
        rightEyeOpenProbability: d('rightEyeOpenProbability'),
        faceSizeRatio: d('faceSizeRatio'),
        // Older native plugins don't send a count — default to 1.
        faceCount: faceCountRaw is num ? faceCountRaw.toInt() : 1,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

// ─── Detector registry ────────────────────────────────────────────────────────
//
// A process-wide factory hook. The liveness flow calls
// [createFaceDetectorService] to obtain a fresh instance per session. By default
// it builds the in-package [NativeFaceDetectorService]; a host may override that
// via [registerFaceDetectorFactory] (e.g. a custom detector, or the stub in
// tests).

FaceDetectorService Function()? _faceDetectorFactory;

/// Overrides the factory used to create the SDK's [FaceDetectorService].
/// Optional — the SDK defaults to the built-in [NativeFaceDetectorService].
/// Call once at startup, before launching the KYC flow.
void registerFaceDetectorFactory(FaceDetectorService Function() factory) {
  _faceDetectorFactory = factory;
}

/// Whether a host has overridden the detector factory.
bool get hasFaceDetectorFactory => _faceDetectorFactory != null;

/// Creates a [FaceDetectorService] — the host override if registered, otherwise
/// the built-in native detector ([NativeFaceDetectorService]).
FaceDetectorService createFaceDetectorService() =>
    (_faceDetectorFactory ?? NativeFaceDetectorService.new)();

// ─── Gesture detection functions ──────────────────────────────────────────────
//
// All functions are pure — they take snapshots / histories and return bool.
// Histories are maintained by the liveness provider (ring buffer, ~20 frames).
// Kept as top-level functions so they can be unit tested without a detector.

/// Detects a nod by watching [xHistory] (headEulerAngleX) dip below −10° then
/// recover above −5°. The caller maintains [xHistory] as a sliding window.
/// Requires at least 2 frames of history.
bool detectNod(List<double> xHistory) {
  if (xHistory.length < 2) return false;
  final minAngle = xHistory.reduce(min);
  final currentAngle = xHistory.last;
  return minAngle < -10 && currentAngle > -5;
}

/// Detects a head turn when [eulerY] exceeds ±25°. Single frame is sufficient.
bool detectTurn(double eulerY) => eulerY.abs() > 25;

/// Detects a blink by watching the average eye-open probability ([earHistory])
/// drop below 0.2 then recover above 0.5. Requires at least 2 frames.
/// (Threshold relaxed 0.15→0.2 from on-device data, where a real blink bottomed
/// out around 0.03–0.15 but only briefly.)
bool detectBlink(List<double> earHistory) {
  if (earHistory.length < 2) return false;
  final hadClose = earHistory.any((v) => v < 0.2);
  final recovered = earHistory.last > 0.5;
  return hadClose && recovered;
}

/// Detects a smile when [smilingProbability] exceeds 0.5. Single frame.
/// (Threshold lowered 0.7→0.5 to pair with the widened Vision smile mapping;
/// a clear smile now lands comfortably above this.)
bool detectSmile(double smilingProbability) => smilingProbability > 0.5;
