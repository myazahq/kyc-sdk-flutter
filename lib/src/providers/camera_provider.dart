import 'dart:io';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'camera_provider.g.dart';

// ─── Camera status ────────────────────────────────────────────────────────────

enum CameraStatus { uninitialized, loading, ready, error, permissionDenied }

// ─── Camera state ─────────────────────────────────────────────────────────────

class CameraState {
  final CameraStatus status;
  final String? error;
  final CameraLensDirection? lensDirection;
  final ResolutionPreset? resolution;

  const CameraState({
    this.status = CameraStatus.uninitialized,
    this.error,
    this.lensDirection,
    this.resolution,
  });

  bool get isReady => status == CameraStatus.ready;
  bool get isLoading => status == CameraStatus.loading;

  /// True when the camera couldn't start because the OS camera permission was
  /// denied (or is blocked at the OS level). The UI shows a dedicated
  /// "allow camera access" screen for this case.
  bool get isPermissionDenied => status == CameraStatus.permissionDenied;

  CameraState copyWith({
    CameraStatus? status,
    String? error,
    CameraLensDirection? lensDirection,
    ResolutionPreset? resolution,
  }) =>
      CameraState(
        status: status ?? this.status,
        error: error,            // explicit null clears the error
        lensDirection: lensDirection ?? this.lensDirection,
        resolution: resolution ?? this.resolution,
      );
}

// ─── Camera notifier ──────────────────────────────────────────────────────────

@riverpod
class CameraNotifier extends _$CameraNotifier {
  CameraController? _controller;

  /// True while the camera is actively delivering frames to an `onImage`
  /// callback — either from [startStream] or [startVideoRecording] with an
  /// onImage callback. We track this ourselves because the plugin's
  /// `value.isStreamingImages` stays true even after [stopVideoRecording]
  /// has torn down the underlying stream surface, and a second
  /// `stopImageStream` call against an abandoned surface throws
  /// "Surface was abandoned" which then crashes the plugin's onCameraError
  /// listener with "controller used after disposed".
  bool _imageStreamActive = false;

  /// True when the active stream is part of a video recording (started via
  /// [startVideoRecording] with an onImage callback). The recording's stop
  /// tears the stream down — `stopImageStream` must not be called separately.
  bool _streamingViaRecording = false;

  @override
  CameraState build() {
    // Dispose the controller when the provider is auto-disposed (screen exit).
    ref.onDispose(_disposeController);
    return const CameraState();
  }

  /// The underlying [CameraController]. Null until [initialize] completes.
  /// Access via `ref.read(cameraNotifierProvider.notifier).controller`.
  CameraController? get controller => _controller;

  /// Freezes/unfreezes auto-exposure.
  ///
  /// Used around a flash-liveness sequence: with AE running, the extra light
  /// from each flash makes the sensor drop its gain, shrinking the very shift
  /// being measured. Locking holds the ambient exposure so baseline and lit
  /// frames are comparable.
  ///
  /// Best-effort — point metering and mode locking aren't universally
  /// supported, and a device that refuses just yields a weaker signal.
  Future<void> setExposureLocked(bool locked) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller
          .setExposureMode(locked ? ExposureMode.locked : ExposureMode.auto);
    } catch (_) {/* unsupported on this device — ignore */}
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises the camera facing [direction] at the given [resolution].
  ///
  /// For liveness/selfie use [CameraLensDirection.front] with
  /// [ResolutionPreset.medium] (720p, per CLAUDE.md).
  /// For document capture use [CameraLensDirection.back].
  Future<void> initialize({
    CameraLensDirection direction = CameraLensDirection.front,
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    if (state.isLoading) return; // already initialising

    state = state.copyWith(status: CameraStatus.loading);
    await _disposeController();

    try {
      final cameras = await availableCameras();

      // No camera on the device (e.g. an iOS Simulator). Surface a clean,
      // user-facing message rather than letting `cameras.first` throw a raw
      // "Bad state: No element" into the error UI.
      if (cameras.isEmpty) {
        state = state.copyWith(
          status: CameraStatus.error,
          error: 'No camera available on this device.',
        );
        return;
      }

      final description = cameras.firstWhere(
        (c) => c.lensDirection == direction,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        description,
        resolution,
        enableAudio: false,
        // ML Kit requires nv21 on Android and bgra8888 on iOS.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      // NOTE: do NOT call controller.lockCaptureOrientation() here. On Android's
      // camerax backend the preview is two nested RotatedBoxes — CameraPreview's
      // outer box (device-orientation driven) and the plugin's inner
      // SurfaceTextureRotatedPreview (= displayRotation − preappliedRotation).
      // Left alone they CANCEL to a net rotation equal to the DISPLAY rotation.
      // lockCaptureOrientation freezes only the OUTER box, desyncing the pair so
      // the net rotation starts following the accelerometer — which is exactly
      // the "feed rotates after a second" bug. Portrait is instead pinned at the
      // display level (SystemChrome.setPreferredOrientations in the flow widget),
      // which keeps displayRotation — and thus the canceled net — at 0/upright.

      // Meter exposure + focus on the centre of the frame. The subject (face or
      // document) is always centred, so this stops a bright background (e.g. a
      // ceiling light or window behind the user) from underexposing it. Best-
      // effort: not all devices support point metering.
      try {
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposurePoint(const Offset(0.5, 0.5));
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {/* unsupported on this device — ignore */}

      _controller = controller;

      state = state.copyWith(
        status: CameraStatus.ready,
        lensDirection: direction,
        resolution: resolution,
      );
    } on CameraException catch (e) {
      // The camera plugin surfaces a denied/blocked OS permission via these
      // codes. Map them to a dedicated permissionDenied status so the UI can
      // show "allow camera access" guidance + an Open Settings action.
      const deniedCodes = {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      };
      if (deniedCodes.contains(e.code)) {
        state = state.copyWith(
          status: CameraStatus.permissionDenied,
          error: 'Camera access is required. Please allow camera access to continue.',
        );
      } else {
        state = state.copyWith(
          status: CameraStatus.error,
          error: e.description ?? 'Camera initialisation failed',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: CameraStatus.error,
        error: 'Camera initialisation failed: $e',
      );
    }
  }

  /// Switches between front and back cameras, re-initialising the controller.
  Future<void> switchCamera() async {
    final current = state.lensDirection ?? CameraLensDirection.front;
    final next = current == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await initialize(
      direction: next,
      resolution: state.resolution ?? ResolutionPreset.medium,
    );
  }

  /// Whether this camera can act as a torch. The plugin exposes no capability
  /// query, so this is "there is a controller" — [setTorch] tolerates a device
  /// that refuses.
  bool get hasTorch => _controller?.value.isInitialized == true;

  /// Switches the torch on/off. Best-effort: not every device or lens supports
  /// it, and a refusal must never break capture.
  Future<void> setTorch(bool enabled) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
    } catch (_) {/* unsupported on this device — ignore */}
  }

  // ── Image stream ───────────────────────────────────────────────────────────

  /// Starts the camera image stream, calling [onImage] for every frame.
  /// Used by document auto-capture (without recording).
  Future<void> startStream(void Function(CameraImage image) onImage) async {
    if (!state.isReady) return;
    if (_imageStreamActive) return;
    await _controller?.startImageStream(onImage);
    _imageStreamActive = true;
    _streamingViaRecording = false;
  }

  /// Stops the camera image stream. No-op when there is no active stream
  /// or when the stream was started via [startVideoRecording] with an
  /// onImage callback (the recording's stop tears that surface down, and
  /// a second stop hits an abandoned surface — which surfaces as
  /// "Surface was abandoned" and crashes the plugin's onCameraError
  /// listener with "controller used after disposed").
  Future<void> stopStream() async {
    if (!_imageStreamActive) return;
    if (_streamingViaRecording) {
      // Will be torn down by stopVideoRecording — don't double-stop.
      return;
    }
    _imageStreamActive = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {/* ignore — stream was already torn down */}
  }

  // ── Video recording ────────────────────────────────────────────────────────

  /// Whether the controller is currently recording video.
  bool get isRecordingVideo => _controller?.value.isRecordingVideo == true;

  /// Starts recording video. Optionally also streams frames to [onImage] —
  /// passing a callback runs video recording and image streaming
  /// concurrently (used by liveness, where ML Kit needs the frames).
  ///
  /// Output is an MP4 file on both iOS and Android.
  Future<void> startVideoRecording({
    void Function(CameraImage image)? onImage,
  }) async {
    if (!state.isReady || _controller == null) return;
    if (_controller!.value.isRecordingVideo) return;
    try {
      await _controller!.startVideoRecording(onAvailable: onImage);
      _streamingViaRecording = onImage != null;
      _imageStreamActive = onImage != null;
    } on CameraException catch (e) {
      // Don't abort the whole flow — recording is best-effort. Log into state
      // so callers can decide whether to surface a warning.
      state = state.copyWith(
        error: e.description ?? 'Video recording failed to start',
      );
    }
  }

  /// Stops video recording and returns the recorded MP4 file path.
  /// Returns null if no recording is in progress or the stop fails.
  ///
  /// The path (rather than bytes) is returned so callers can hand it straight
  /// to `VideoCompress.compressVideo` before reading the (smaller) bytes for
  /// upload.
  ///
  /// Always tears down the image stream — the camera plugin couples the
  /// stream surface to the recording when started via
  /// `startVideoRecording(onAvailable:)`, so callers must not call
  /// [stopStream] separately after this returns.
  Future<String?> stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      _streamingViaRecording = false;
      _imageStreamActive = false;
      return null;
    }
    try {
      final xFile = await _controller!.stopVideoRecording();
      _streamingViaRecording = false;
      _imageStreamActive = false;
      return xFile.path;
    } on CameraException catch (e) {
      _streamingViaRecording = false;
      _imageStreamActive = false;
      state = state.copyWith(
        error: e.description ?? 'Video recording failed to stop',
      );
      return null;
    } catch (_) {
      _streamingViaRecording = false;
      _imageStreamActive = false;
      return null;
    }
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  /// Takes a still photo. Returns the image bytes, or null if the camera
  /// is not ready. Stops any running stream first (required on some platforms).
  ///
  /// If a video recording is in progress, the caller is expected to have
  /// stopped it via [stopVideoRecording] beforehand — `takePicture` cannot
  /// run concurrently with recording on Android.
  Future<Uint8List?> captureImage() async {
    if (!state.isReady || _controller == null) return null;

    // Stop the image stream before takePicture — required on some Android
    // devices. [stopStream] is a no-op when the stream was started via
    // startVideoRecording (the recording's stop already tore it down).
    if (_imageStreamActive) await stopStream();

    try {
      final xFile = await _controller!.takePicture();
      final bytes = await xFile.readAsBytes();
      // The image stream is left stopped — callers re-register via
      // startStream() if they need it again.
      return bytes;
    } on CameraException catch (e) {
      state = state.copyWith(
        status: CameraStatus.error,
        error: e.description ?? 'Capture failed',
      );
      return null;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _disposeController() async {
    final ctrl = _controller;
    final hadStandaloneStream =
        _imageStreamActive && !_streamingViaRecording;
    _controller = null;
    _streamingViaRecording = false;
    _imageStreamActive = false;
    if (ctrl == null) return;
    if (ctrl.value.isRecordingVideo) {
      try {
        await ctrl.stopVideoRecording();
      } catch (_) {/* ignore — controller is being torn down */}
    }
    // Only stop the standalone image stream — `stopVideoRecording` already
    // tore down the stream surface when recording was started with an
    // onImage callback, and a second stop hits an abandoned surface.
    if (hadStandaloneStream) {
      try {
        await ctrl.stopImageStream();
      } catch (_) {/* ignore */}
    }
    try {
      await ctrl.dispose();
    } catch (_) {/* ignore */}
  }
}
