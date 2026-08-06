import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show Uint8List, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../config/capture_config.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../liveness/face_detection.dart';
import '../liveness/capture_tuning.dart';
import '../liveness/face_rgb_sampler.dart';
import '../liveness/flash_challenge.dart';
import '../liveness/flash_detector.dart';
import '../liveness/liveness_types.dart';
import '../liveness/native_liveness_recorder.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../providers/liveness_provider.dart';
import '../services/api_service.dart';
import '../services/image_service.dart';
import '../services/kyc_error_mapper.dart';
import '../services/media_compress_service.dart';
import '../services/retry.dart';
import '../utils/permissions.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/camera_permission_priming_view.dart';
import '../widgets/ready_primer.dart';
import '../widgets/ready_primer_content.dart';
import '../widgets/liveness_avatar.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/native_camera_preview.dart';
import '../widgets/myaza_button.dart';

// ─── Liveness screen ──────────────────────────────────────────────────────────

class LivenessScreen extends ConsumerStatefulWidget {
  /// Fires for technical errors raised on this screen (camera permission
  /// denied, selfie upload failed after retries).
  final void Function(KYCError error)? onError;

  const LivenessScreen({super.key, this.onError});

  @override
  ConsumerState<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends ConsumerState<LivenessScreen>
    with WidgetsBindingObserver {
  final FaceDetectorService _detector = createFaceDetectorService();
  final _TtsService _tts = _TtsService();
  final _BrightnessSampler _brightnessSampler = _BrightnessSampler();

  bool _processing = false;
  bool _capturingHandled = false;

  // Marks the on-screen preview circle so the flash overlay can punch a hole at
  // its exact position — the real preview shows through, fixed, instead of a
  // second preview appearing elsewhere and making it jump.
  final GlobalKey _previewKey = GlobalKey();

  // When a face was last actually detected. Used to refuse a capture when the
  // face has left — during the flash the fullscreen overlay hides the preview,
  // so a user who drifts out of frame gets a selfie of nothing, which then
  // fails facial comparison. Null until the first detection.
  DateTime? _lastFaceSeenAt;
  bool _completionHandled = false;
  int _sensorOrientation = 0;
  bool _isDim = false;
  bool _isBright = false;
  // True while _init() is running — used to ignore the inactive→resumed bounce
  // caused by the OS camera-permission prompt (the in-flight init handles it).
  bool _initializing = false;
  // Set when the explicit camera-permission check fails. The Android native
  // recorder path doesn't surface a denial through cameraNotifier, so this is
  // the signal that drives the permission screen there.
  bool _permissionDenied = false;
  // Ensures the camera_permission_denied error is reported to onError once.
  bool _cameraPermissionReported = false;
  // Show the "Allow camera access" primer before the OS prompt (Stripe-style),
  // unless the camera is already granted. The camera (and therefore the OS
  // prompt) only starts once the user taps "Grant access".
  /// Whether the user has acknowledged the "here's what happens next"
  /// screen. Gates the camera so it never opens unannounced.
  bool _ready = false;
  bool _showPrimer = false;

  // Latest camera-stream frame, kept whole (not just its bytes) so flash
  // liveness can sample the face region's mean RGB from it (iOS).
  CameraImage? _latestImage;

  // Latest face-region RGB shipped by the native recorder (Android) — the flash
  // reflection source there, since the raw frame never reaches Dart.
  List<double>? _latestNativeRgb;

  /// The per-frame face-region RGB source for the flash, per platform: the
  /// native recorder's shipped RGB on Android, else sampled from the cached
  /// CameraImage on iOS.
  List<double>? _flashRgbSample() {
    if (_useNativeRecorder) return _latestNativeRgb;
    final img = _latestImage;
    return img != null ? sampleFrameRgb(img) : null;
  }

  /// Fullscreen flash overlay color; null = neutral. A ValueNotifier so painting
  /// a flash repaints only the overlay — a setState per flash would rebuild the
  /// camera preview mid-sequence and disturb the very frames being sampled.
  final ValueNotifier<Color?> _flashColor = ValueNotifier<Color?>(null);

  /// The flash outcome, submitted as the integrity claim. Null = didn't run.
  FlashResult? _flashResult;

  // The most recent frame DETECTION confirmed holds a face. The selfie (iOS
  // fast path) is encoded from THIS, not the latest frame — the latest is
  // already blank the instant the face leaves. Detection lags the stream by
  // ~100ms, so at capture time the newest frame and the last confirmed-face
  // frame are different frames; encoding the newest one is how a face pulled
  // away at the last instant produced a blank selfie. This one always holds a
  // real face (bounded fresh by the capture gate), never nothing.
  Uint8List? _lastFaceFrameBytes;
  int _lastFaceFrameWidth = 0;
  int _lastFaceFrameHeight = 0;
  int _lastFaceFrameStride = 0;

  bool _isUploadingSelfie = false;
  String? _selfieUploadError;
  ({int attempt, int total})? _selfieRetryInfo;

  // Liveness video file path — recorded after the challenge sequence and
  // compressed + uploaded alongside the selfie. Kept locally (as a path so it
  // can be handed to VideoCompress) until [_uploadSelfieAndVideo].
  String? _livenessVideoPath;

  // The selfie is shown immediately while the gesture recording finalizes in the
  // background (MP4 muxer flush). This future tracks that finalization so the
  // upload step can await it before reading [_livenessVideoPath] — otherwise a
  // user who taps Continue very fast would lose the (best-effort) liveness video.
  Future<void>? _pendingRecordingStop;

  // ── Android native recorder ────────────────────────────────────────────────
  // On Android we use a native CameraX recorder that runs ONE ImageAnalysis
  // stream fanned to both ML Kit (gesture signals) AND a MediaCodec encoder
  // (a clip that shows the gestures). This sidesteps the CameraX use-case cap
  // that breaks record-while-detecting via the Flutter camera plugin. iOS and
  // document/selfie capture keep using the Flutter camera plugin.
  bool get _useNativeRecorder => Platform.isAndroid;
  NativeLivenessRecorder? _nativeRecorder;
  int? _nativeTextureId;
  int _nativePreviewW = 0;
  int _nativePreviewH = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final voice = ref.read(kycConfigProvider).voiceGuidance;
    _tts.initialize(enabled: voice.enabled, language: voice.resolvedLanguage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrime());
  }

  /// Show the "Allow camera access" primer before requesting permission, unless
  /// the camera is already granted (in which case we start straight away).
  /// Re-invoked when the user acknowledges the ready screen — until then the
  /// camera stays shut, which is the whole point of that screen.
  Future<void> _maybePrime() async {
    if (!_ready) return;
    if (await hasCameraPermission()) {
      if (!mounted) return;
      _init();
    } else {
      if (!mounted) return;
      setState(() => _showPrimer = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detector.dispose();
    _tts.dispose();
    _flashColor.dispose();
    _nativeRecorder?.dispose();
    super.dispose();
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────
  //
  // iOS (and Android) release the camera when the app is backgrounded — e.g.
  // when the user leaves to Settings to change the camera permission, or while
  // the OS permission prompt is up. On return the old CameraController is dead,
  // so the preview/stream would freeze. Re-initialise the whole pipeline on
  // resume so the camera comes back without needing a restart.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state != AppLifecycleState.resumed) return;
    // iOS only. The freeze this recovers from is an AVFoundation quirk (the
    // CameraController dies when the app is backgrounded). On Android the
    // CameraX-backed pipeline (Flutter camera plugin + our native recorder) is
    // lifecycle-aware already, and a manual dispose+reinit on resume races
    // CameraX's recorder teardown → a fatal "onConfigured in STOPPING state"
    // assertion. So leave Android's camera lifecycle to CameraX.
    if (!Platform.isIOS) return;
    // Nothing to restore while a pre-camera screen is up — and restoring would
    // START the camera behind it, which is exactly what those screens exist to
    // prevent. Backgrounding the app on the ready screen (a notification, an app
    // switch, the previous step's NFC sheet) used to open the selfie camera with
    // the primer still on top: filming before the user ever said go.
    if (!_ready || _showPrimer) return;
    // The system permission prompt also bounces us through inactive→resumed —
    // the in-flight _init() (awaiting initialize()) handles that, so skip while
    // it runs. Don't disturb the selfie-review/complete screen (no live camera).
    if (_initializing) return;
    if (ref.read(livenessNotifierProvider).phase == LivenessPhase.complete) {
      return;
    }
    _resumeAfterBackground();
  }

  /// Tears down stale camera/recorder state and re-initialises a fresh liveness
  /// attempt after the app returns to the foreground.
  Future<void> _resumeAfterBackground() async {
    _nativeRecorder?.dispose();
    _nativeRecorder = null;
    _capturingHandled = false;
    _completionHandled = false;
    _processing = false;
    _isDim = false;
    _isBright = false;
    _livenessVideoPath = null;
    _pendingRecordingStop = null;
    _cameraPermissionReported = false;
    _brightnessSampler.reset();
    if (mounted) setState(() => _nativeTextureId = null);
    ref.read(livenessNotifierProvider.notifier).reset();
    await _init();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await _initInternal();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initInternal() async {
    if (!mounted) return;

    // Android: explicit camera-permission gate. The native recorder owns the
    // camera directly (not via cameraNotifier), so a denial wouldn't otherwise
    // surface — without this the flow would start the liveness state machine
    // (frame + voice) with no feed and no error. iOS is left to the camera
    // controller's own denial signal (and avoids needing permission_handler
    // Podfile macros).
    if (Platform.isAndroid) {
      final granted = await requestCameraPermission();
      if (!mounted) return;
      if (!granted) {
        _tts.stop();
        _reportCameraPermissionDenied(null);
        setState(() => _permissionDenied = true);
        return;
      }
      if (_permissionDenied) setState(() => _permissionDenied = false);
    }

    // Android: native CameraX recorder (single stream → ML Kit + encoder).
    if (_useNativeRecorder) {
      await _initNativeRecorder();
      return;
    }

    final cameras = await availableCameras();
    if (!mounted) return;

    // No camera (e.g. iOS Simulator) — let the camera provider attempt and fail
    // gracefully into its error state so the loading view shows "Camera
    // unavailable" instead of crashing. Keeps the SDK runnable on simulators.
    if (cameras.isEmpty) {
      await ref.read(cameraNotifierProvider.notifier).initialize(
            direction: CameraLensDirection.front,
            resolution: CaptureConfig.livenessResolution,
          );
      return;
    }

    final frontDesc = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _sensorOrientation = frontDesc.sensorOrientation;

    _detector.initialize();

    // High (~1080p) preserves facial detail for accurate server-side matching;
    // the selfie still is compressed moderately (quality 85, ≥1080 px). The
    // recorded liveness video is shrunk by VideoCompress at encode time, so a
    // high camera preset doesn't bloat it. Tune via CaptureConfig.livenessResolution.
    await ref.read(cameraNotifierProvider.notifier).initialize(
          direction: CameraLensDirection.front,
          resolution: CaptureConfig.livenessResolution,
        );
    if (!mounted) return;

    // If the camera didn't come up (permission denied / unavailable), do NOT
    // start the gesture stream or the liveness state machine — otherwise the
    // flow would advance to "positioning" and the voice prompt would speak even
    // though only the permission screen is showing. The build() method renders
    // the CameraPermissionView for this state.
    if (!ref.read(cameraNotifierProvider).isReady) {
      _tts.stop();
      return;
    }

    // Start the camera frame stream that feeds ML Kit gesture detection.
    //
    // The liveness clip should show the gestures being performed, so on iOS we
    // record video AND stream frames concurrently for the whole session
    // (CameraController supports this via startVideoRecording(onAvailable:)).
    // On Android we DON'T: many CameraX devices cap concurrent use cases and
    // enabling VideoCapture silently starves the ImageAnalysis stream, breaking
    // gesture detection — so Android keeps a plain gesture stream and records a
    // short clip at capture time instead (see [_handleCapture]).
    await _startGestureFeed();
    if (!mounted) return;

    ref.read(livenessNotifierProvider.notifier).startDetection();
  }

  /// Android: start the native CameraX recorder. It owns the camera, streams
  /// face signals to us, renders the preview into a Flutter texture, and records
  /// a gesture-showing clip. Gesture detection runs natively (ML Kit) on the
  /// same stream the encoder uses.
  Future<void> _initNativeRecorder() async {
    final recorder = NativeLivenessRecorder();
    _nativeRecorder = recorder;
    try {
      final textureId = await recorder.start(onFace: _onNativeFace);
      if (!mounted) {
        recorder.dispose();
        return;
      }
      // Record the whole session so the clip captures the gestures.
      await recorder.startRecording();
      if (kDebugMode) {
        debugPrint(
          'KYC native preview: rotation=${recorder.rotationDegrees} '
          'buffer=${recorder.previewWidth}x${recorder.previewHeight}',
        );
      }
      setState(() {
        _nativeTextureId = textureId;
        _nativePreviewW = recorder.previewWidth;
        _nativePreviewH = recorder.previewHeight;
      });
      ref.read(livenessNotifierProvider.notifier).startDetection();
    } catch (e) {
      // Native recorder failed — surface the "camera unavailable" state.
      recorder.dispose();
      _nativeRecorder = null;
      if (!mounted) return;
      ref.read(cameraNotifierProvider.notifier).initialize(
            direction: CameraLensDirection.front,
            resolution: CaptureConfig.livenessResolution,
          );
    }
  }

  /// Face signals from the native recorder → liveness provider. The native side
  /// already did ML Kit detection, so we just forward the result.
  void _onNativeFace(LivenessFaceData? data) {
    if (!mounted) return;
    final notifier = ref.read(livenessNotifierProvider.notifier);
    if (data != null) {
      _lastFaceSeenAt = DateTime.now();
      // The native (Android) recorder owns the camera, so the raw frame never
      // reaches _onCameraImage — it ships the mean luma + face-region RGB with
      // the face data so lighting guidance AND flash liveness work here.
      if (data.brightness >= 0) _checkBrightnessLuma(data.brightness);
      _latestNativeRgb = data.faceRgb; // flash reflection source on Android
      notifier.processFrame(data);
    } else {
      notifier.reportNoFace();
    }
  }

  // ── Camera image stream ────────────────────────────────────────────────────

  void _onCameraImage(CameraImage image) {
    if (_processing || !mounted) return;
    _processing = true;

    // Kept whole so flash liveness can sample the face-region RGB. The selfie is
    // NOT encoded from here — it comes from _lastFaceFrameBytes (the last frame
    // with a confirmed face), set in the detection callback below.
    _latestImage = image;

    // Sample brightness (throttled to ~800ms). Only update state when it
    // actually changes to avoid unnecessary rebuilds.
    _checkBrightness(image);

    _detector
        .detect(image, sensorOrientation: _sensorOrientation)
        .then((faceData) {
      if (!mounted) { _processing = false; return; }
      final notifier = ref.read(livenessNotifierProvider.notifier);
      if (faceData != null) {
        _lastFaceSeenAt = DateTime.now();
        // Snapshot THIS frame (the one detection ran on) as the selfie source.
        // `image` here is the exact frame that was found to contain a face.
        if (_selfieFromCachedFrame && image.planes.isNotEmpty) {
          final plane = image.planes.first;
          _lastFaceFrameBytes = plane.bytes;
          _lastFaceFrameWidth = image.width;
          _lastFaceFrameHeight = image.height;
          _lastFaceFrameStride = plane.bytesPerRow;
        }
        notifier.processFrame(faceData);
      } else {
        notifier.reportNoFace();
      }
      _processing = false;
    }).catchError((_) { _processing = false; });
  }

  // iOS / Flutter-camera path: sample brightness from the raw frame.
  void _checkBrightness(CameraImage image) =>
      _applyLightLevel(_brightnessSampler.sample(image));

  // Android native-recorder path: classify from the natively-computed luma.
  void _checkBrightnessLuma(double luma) =>
      _applyLightLevel(_brightnessSampler.sampleLuma(luma));

  void _applyLightLevel(_LightLevel? level) {
    if (level == null) return; // not yet time to sample
    final nowDim = level == _LightLevel.dark;
    final nowBright = level == _LightLevel.bright;
    if ((nowDim != _isDim || nowBright != _isBright) && mounted) {
      setState(() {
        _isDim = nowDim;
        _isBright = nowBright;
      });
    }
    // Feed the gate into the liveness state machine so it won't start
    // challenges / auto-capture in poor light (mirrors the web SDK).
    ref.read(livenessNotifierProvider.notifier).setLightingGuidance(
          nowDim ? 'dark' : (nowBright ? 'bright' : null),
        );
  }

  // ── Phase handlers ─────────────────────────────────────────────────────────

  /// True where we record the liveness clip concurrently with gesture detection,
  /// so the clip actually shows the gestures being performed AND the selfie is
  /// captured instantly afterwards (no record-then-capture wait).
  ///
  /// **iOS only.** iOS (AVFoundation) happily runs a concurrent video recording
  /// + frame stream on one session. Android (CameraX) does NOT reliably: it caps
  /// concurrent use cases and starves the ImageAnalysis stream while VideoCapture
  /// runs, so ML Kit receives no frames and gesture detection breaks ("no face
  /// detected" — confirmed on a Galaxy S24). On Android we therefore keep a plain
  /// gesture stream and record a short clip at capture time instead (the clip
  /// won't show the gestures, but detection works — the right trade-off).
  bool get _recordsDuringGestures => Platform.isIOS;

  /// iOS-only: encode the selfie straight from a cached BGRA stream frame (no
  /// takePicture / capture-session switch). Android uses takePicture() instead.
  bool get _selfieFromCachedFrame => Platform.isIOS;

  /// Starts the camera feed that drives ML Kit gesture detection. On iOS this is
  /// a video recording with a concurrent frame stream (records the gestures); on
  /// Android it's a plain image stream.
  Future<void> _startGestureFeed() async {
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    if (_recordsDuringGestures) {
      _livenessVideoPath = null; // a fresh recording is in progress
      await cameraNotifier.startVideoRecording(onImage: _onCameraImage);
    } else {
      await cameraNotifier.startStream(_onCameraImage);
    }
  }

  /// Paints the randomized color sequence and correlates the face's reflection.
  ///
  /// Never throws and never blocks completion: a null result is submitted as
  /// "no flash claim" rather than a failure. Ambient light bright enough to
  /// wash out the reflection is a normal outcome (documented fail-soft), and
  /// the server independently re-scores the recording either way — so failing
  /// the user here would lock people out in daylight for no security gain.
  /// Whether a face has been detected within [within]. Fails closed (no
  /// detection yet ⇒ false).
  ///
  /// Used by the flash-abort with a generous window: a full-screen colour flash
  /// can make the face momentarily undetectable, and aborting on a single
  /// dropped frame would be worse than finishing a sequence the face is still
  /// in.
  bool _faceRecentlyPresent(Duration within) {
    final seen = _lastFaceSeenAt;
    return seen != null && DateTime.now().difference(seen) <= within;
  }

  /// Waits for a FRESH face detection (one that lands after this call), up to
  /// [timeout]. Returns false if none arrives.
  ///
  /// The capture gate uses this instead of a recency threshold on the last
  /// timestamp: a stale timestamp from just before the face left could still
  /// fall inside a short window, and that is exactly the "captured a blank
  /// selfie" case. Demanding a detection AFTER the flash ends — with the overlay
  /// gone and detection reliable again — means the face must be there NOW, not
  /// merely have been there a moment ago.
  Future<bool> _awaitFreshFace(Duration timeout) async {
    final since = DateTime.now();
    final deadline = since.add(timeout);
    while (mounted && DateTime.now().isBefore(deadline)) {
      final seen = _lastFaceSeenAt;
      if (seen != null && seen.isAfter(since)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return false;
  }

  /// Drops back to positioning after the face was lost, instead of capturing an
  /// empty frame. The camera keeps running, so the user simply re-frames and the
  /// gate fires again — no teardown, no permission re-prompt.
  Future<void> _restartAfterFaceLost() async {
    _capturingHandled = false;
    _flashResult = null; // a partial flash from the abandoned attempt isn't ours to claim
    ref.read(livenessNotifierProvider.notifier).reset();
  }

  /// The preview circle's rect in screen coordinates, for the flash hole. Null
  /// if it can't be measured (fall back to a plain fullscreen flash).
  Rect? _previewCircleRect() {
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _runFlashChallenge() async {
    final config = ref.read(kycConfigProvider);
    if (!config.livenessMode.runsFlash) return;

    _tts.stop(); // the sequence is visual; spoken guidance would talk over it

    // Painted into the ROOT overlay, above the sheet. The screen is the light
    // source here, so the color has to fill the display — a fill inside the
    // sheet's body would leave the status bar and backdrop dark and cut the
    // emitted light, which is the signal being measured.
    //
    // A live preview circle rides ON TOP of the flash so the user can still see
    // themselves and stay in frame — the fullscreen colour used to blind them,
    // which is how a drifted face went unnoticed until it captured nothing. The
    // circle is ~1-2% of the screen, so it barely dents the emitted light, and
    // because it looks the same in the neutral and lit frames it cancels out of
    // the baseline-vs-lit comparison rather than corrupting it.
    final overlay = Overlay.of(context, rootOverlay: true);
    // Where the real preview circle sits on screen. The flash paints everywhere
    // EXCEPT here, so the live preview shows through the hole — fixed in place,
    // never a second preview that jumps in and out (which is what shook).
    final holeRect = _previewCircleRect();
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<Color?>(
        valueListenable: _flashColor,
        builder: (_, color, __) => IgnorePointer(
          child: color == null
              ? const SizedBox.shrink()
              : SizedBox.expand(
                  child: CustomPaint(
                    painter: _FlashHolePainter(color: color, hole: holeRect),
                  ),
                ),
        ),
      ),
    );
    overlay.insert(entry);

    // Raise the screen and freeze white balance / exposure BEFORE any sampling.
    // Auto white balance exists to cancel colour casts, so left running it
    // erases the reflection we measure; and the screen is the light source, so
    // a dim display simply produces nothing to measure.
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    await beginFlashTuning(
      lockExposure: () => cameraNotifier.setExposureLocked(true),
    );

    try {
      if (!mounted) return;
      _flashResult = await runFlashChallenge(
        latestRgb: _flashRgbSample,
        paint: (color) => _flashColor.value = color,
        // Per-flow sequence length (default 4), clamped to the palette by
        // generateFlashSequence.
        sequence: generateFlashSequence(config.flashSequenceLength),
        // Abort if the face has been gone for a while — no point flashing at an
        // empty frame for the full sequence. Generous window so a colour flash
        // briefly hiding the face doesn't cut a sequence it's still in.
        // Also stops the moment the session can no longer vouch for who is in
        // frame — a second face during the flash used to be ignored outright,
        // which made the one measurement that proves liveness the one moment
        // anybody could stand in shot.
        isActive: () =>
            mounted &&
            !ref.read(livenessNotifierProvider.notifier).integrityBroken &&
            _faceRecentlyPresent(const Duration(milliseconds: 1500)),
      );
    } finally {
      _flashColor.value = null;
      entry.remove();
      // Unconditional: the user's brightness is theirs, and a still-locked
      // exposure would degrade the selfie captured moments later.
      await endFlashTuning(
        unlockExposure: () => cameraNotifier.setExposureLocked(false),
      );
    }
  }

  Future<void> _handleCapture() async {
    if (_capturingHandled) return;
    _capturingHandled = true;

    // Flash liveness runs HERE — after positioning/gestures, before the still,
    // while the liveness video is recording so the flashes land inside the clip
    // the server re-scores. Both platforms record continuously by now: iOS via
    // the gesture recording (since the step opened), Android via the native
    // CameraX recorder (started at init). _runFlashChallenge no-ops off flash
    // mode and reads its reflection samples per platform (_flashRgbSample).
    if (_recordsDuringGestures || _useNativeRecorder) await _runFlashChallenge();
    if (!mounted) return;

    // A second face appeared while the flash ran. Aborting the flash is not
    // enough on its own — the still is taken moments later, and capturing it
    // would attribute somebody else's challenges to whoever is in shot now.
    final notifier = ref.read(livenessNotifierProvider.notifier);
    if (notifier.integrityBroken) {
      _capturingHandled = false;
      // A partial flash from an attempt we're discarding isn't ours to claim.
      _flashResult = null;
      // Report NOW, not during the flash: the overlay is gone, so the screen
      // can re-lay out without the preview circle sliding away from the hole
      // that was cut for it.
      notifier.reportIntegrityFailure();
      return;
    }

    // Let the face settle after the final gesture (a nod/turn leaves the head
    // still moving for a moment). The frame stream keeps running during this
    // delay, so the cached frame advances to a steadier one before capture.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Don't capture an empty frame. The face can leave during the flash and
    // every branch below would happily save whatever's there. Require a FRESH
    // detection now — the face must be present at capture time, not merely have
    // been a moment ago — else drop back to positioning and re-frame.
    if (!await _awaitFreshFace(const Duration(milliseconds: 1500))) {
      await _restartAfterFaceLost();
      return;
    }
    if (!mounted) return;

    // Android native path: grab the selfie still straight from the live analysis
    // stream and show it immediately, THEN finalize the gesture recording in the
    // background. captureStill() reads the latest stream frame and is independent
    // of the MediaCodec recording, so we don't make the user wait for the MP4
    // muxer to flush (that finalization was the post-gesture stall). Mirrors the
    // iOS fast path.
    final nativeRecorder = _nativeRecorder;
    if (_useNativeRecorder && nativeRecorder != null) {
      final selfie = await nativeRecorder.captureStill(
        quality: CaptureConfig.selfieImageQuality,
      );
      if (!mounted) return;

      if (selfie != null) {
        // The native still is already a rotated, mirrored JPEG. Run the standard
        // selfie pipeline (decode → enhance → size-bound under 1 MB), then show.
        final processed = await processSelfieImage(selfie);
        if (!mounted) return;
        ref
            .read(livenessNotifierProvider.notifier)
            .captureSelfieEncoded(processed);
        // Stop the gesture recording after the selfie is already shown — the
        // video→idle teardown never blocks the user. The upload step awaits this.
        _pendingRecordingStop = _stopNativeRecordingInBackground(nativeRecorder);
        return;
      }

      // Still capture failed — discard the recording and restart so the user can
      // retry.
      _capturingHandled = false;
      _livenessVideoPath = null;
      await nativeRecorder.stopRecording();
      if (!mounted) return;
      await nativeRecorder.startRecording();
      ref.read(livenessNotifierProvider.notifier).reset();
      return;
    }

    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);

    // iOS fast path: encode the selfie from the live frame cached during "hold
    // still" — no takePicture(), no video→photo capture-session switch (that
    // switch was the multi-second stall). The gesture video keeps recording; we
    // stop it in the background after the selfie is shown.
    if (_selfieFromCachedFrame) {
      // The last frame with a CONFIRMED face, not the latest frame — the latest
      // may be blank if the face just left. The capture gate above guaranteed a
      // fresh face, so this is both recent AND non-empty.
      final frame = _lastFaceFrameBytes;
      Uint8List? selfie;
      if (frame != null && _lastFaceFrameWidth > 0) {
        selfie = await processSelfieFrame(
          bytes: frame,
          width: _lastFaceFrameWidth,
          height: _lastFaceFrameHeight,
          bytesPerRow: _lastFaceFrameStride,
          bgra: true,           // iOS stream is BGRA8888
          // The iOS camera plugin already delivers front-camera stream frames
          // mirrored (matching the mirrored preview), so flipping again would
          // UN-mirror the selfie. Keep it as-is to preserve the selfie mirror.
          mirror: false,
        );
      }
      if (!mounted) return;

      if (selfie != null) {
        ref
            .read(livenessNotifierProvider.notifier)
            .captureSelfieEncoded(selfie);
        _pendingRecordingStop = _stopRecordingInBackground(cameraNotifier);
        return;
      }
      // Frame encode failed — fall through to the still-capture path.
    }

    if (_recordsDuringGestures) {
      // iOS fallback (cached-frame encode failed): the gesture video has been
      // recording — stop it and grab its path, then take the still.
      final videoPath = await cameraNotifier.stopVideoRecording();
      if (!mounted) return;
      if (videoPath != null) _livenessVideoPath = videoPath;
    } else {
      // Android: gesture detection ran on a plain image stream (CameraX can't
      // reliably record + stream at once), so nothing is recording yet. Record a
      // short liveness clip now, before the still. (Clip shows the post-gesture
      // face rather than the gestures themselves — the working-detection trade.)
      await cameraNotifier.startVideoRecording();
      if (!mounted) return;
      // Flash inside the recording window so the clip carries the sequence the
      // server verifies. When flash isn't configured this is the original
      // fixed-length clip.
      if (ref.read(kycConfigProvider).livenessMode.runsFlash) {
        await _runFlashChallenge();
      } else {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      final videoPath = await cameraNotifier.stopVideoRecording();
      if (!mounted) return;
      if (videoPath != null) _livenessVideoPath = videoPath;
    }

    final bytes = await cameraNotifier.captureImage();
    if (!mounted) return;

    if (bytes == null) {
      _capturingHandled = false;
      _livenessVideoPath = null;
      await _startGestureFeed();
      ref.read(livenessNotifierProvider.notifier).reset();
      return;
    }

    await ref.read(livenessNotifierProvider.notifier).captureSelfie(bytes);
  }

  /// Stops the gesture recording after the selfie is already shown, so the
  /// video→idle teardown never blocks the user. Best-effort.
  Future<void> _stopRecordingInBackground(CameraNotifier cameraNotifier) async {
    try {
      final videoPath = await cameraNotifier.stopVideoRecording();
      if (videoPath != null) _livenessVideoPath = videoPath;
    } catch (_) {
      // Best-effort — proceed without a liveness video.
    }
  }

  /// Android equivalent of [_stopRecordingInBackground]: finalizes the native
  /// gesture recording (MP4 muxer flush) after the selfie is already on screen,
  /// so the user never waits on it. Best-effort.
  Future<void> _stopNativeRecordingInBackground(
      NativeLivenessRecorder recorder) async {
    try {
      final videoPath = await recorder.stopRecording();
      if (videoPath != null) _livenessVideoPath = videoPath;
    } catch (_) {
      // Best-effort — proceed without a liveness video.
    }
  }

  void _handleComplete(String selfieBase64) {
    if (_completionHandled) return;
    _completionHandled = true;

    // Record WHICH liveness method ran and how it went. Submitted with the
    // verification so the server can re-score the recording against the claimed
    // flash sequence — without this the capture is unverifiable after the fact.
    ref.read(kYCNotifierProvider.notifier).setLivenessIntegrity(
          livenessIntegrityClaim(
            mode: ref.read(kycConfigProvider).livenessMode,
            flash: _flashResult,
          ),
        );
    // Eagerly upload the selfie (and best-effort liveness video) the moment it's
    // shown, so the network round-trip overlaps the user's review instead of
    // blocking after they tap Continue. Both review buttons are disabled while
    // _isUploadingSelfie is true, so this in-flight upload can't race a retake;
    // Continue then advances instantly once the mediaId is set.
    _uploadSelfieAndVideo();
  }

  /// Compress + upload the captured selfie to /api/kyc/upload (plus the
  /// best-effort liveness video) and store the returned mediaIds in state.
  /// Runs eagerly when the selfie is first shown ([_handleComplete]); does NOT
  /// advance the flow — [_onSelfieAccepted] does that once the user confirms.
  Future<void> _uploadSelfieAndVideo() async {
    if (_isUploadingSelfie) return;
    final selfieBase64 = ref.read(livenessNotifierProvider).selfieBase64;
    if (selfieBase64 == null) return;

    setState(() {
      _isUploadingSelfie = true;
      _selfieUploadError = null;
      _selfieRetryInfo = null;
    });

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final api = notifier.api;

      // The selfie was already encoded under CaptureConfig.selfieMaxBytes
      // (<1 MB) while keeping facial detail — upload as-is; a second pass would
      // only cost quality.
      final bytes = base64Decode(selfieBase64);
      if (kDebugMode) {
        debugPrint(
          'KYC selfie upload size: ${(bytes.length / 1024).toStringAsFixed(0)} KB',
        );
      }
      if (!mounted) return;

      // Retried on transient failures (network / timeout / 5xx).
      final selfieMediaId = await withRetry(
        () => api.upload(bytes, 'image/jpeg', MediaType.selfie),
        onRetry: (attempt, total) {
          if (mounted) setState(() => _selfieRetryInfo = (attempt: attempt, total: total));
        },
      );
      if (!mounted) return;

      setState(() => _selfieRetryInfo = null);
      notifier.setMediaId('selfie', selfieMediaId);

      // The gesture recording finalizes in the background after the selfie is
      // shown; wait for that (bounded) so its path is set before we read it. A
      // stuck muxer can't hang the upload — we proceed without the video.
      if (_pendingRecordingStop != null) {
        await _pendingRecordingStop!
            .timeout(const Duration(seconds: 3), onTimeout: () {});
        if (!mounted) return;
      }

      // Upload the recorded liveness video (best-effort — proceed if the
      // recording was unavailable or its upload fails after retries).
      if (_livenessVideoPath != null) {
        try {
          final videoBytes = await compressVideoToBytes(
            _livenessVideoPath!,
            label: 'liveness video',
          );
          if (!mounted) return;
          final videoMediaId = await withRetry(
            () => api.upload(videoBytes, 'video/mp4', MediaType.livenessVideo),
          );
          if (!mounted) return;
          notifier.setMediaId('livenessVideo', videoMediaId);
        } catch (_) {
          // Best-effort — the verification proceeds without the liveness video.
        }
      }

      setState(() => _isUploadingSelfie = false);
    } on KYCApiException catch (e) {
      if (!mounted) return;
      // Retries exhausted — show the inline error AND report a typed error.
      final kycError = mapToKycError(e, context: ErrorContext.upload);
      setState(() {
        _isUploadingSelfie = false;
        _selfieRetryInfo = null;
        _selfieUploadError = kycError.message;
      });
      widget.onError?.call(kycError);
    } catch (e) {
      if (!mounted) return;
      final kycError = mapToKycError(e, context: ErrorContext.upload);
      setState(() {
        _isUploadingSelfie = false;
        _selfieRetryInfo = null;
        _selfieUploadError = kycError.message;
      });
      widget.onError?.call(kycError);
    }
  }

  /// Continue button. The upload was kicked off eagerly when the selfie was
  /// shown, so usually the selfie mediaId is already set and we advance
  /// instantly. If the eager upload failed (button reads "Try Again"), retry
  /// it first, then advance only once the selfie mediaId is present.
  Future<void> _onSelfieAccepted() async {
    final notifier = ref.read(kYCNotifierProvider.notifier);

    if (ref.read(kYCNotifierProvider).mediaIds.selfie == null) {
      await _uploadSelfieAndVideo();
      if (!mounted) return;
      if (ref.read(kYCNotifierProvider).mediaIds.selfie == null) return;
    }

    notifier.nextStep();
  }

  void _retryLiveness() {
    setState(() {
      _capturingHandled = false;
      _completionHandled = false;
      _processing = false;
      _isDim = false;
      _livenessVideoPath = null;
      _pendingRecordingStop = null;
    });
    _brightnessSampler.reset();
    ref.read(livenessNotifierProvider.notifier).reset();

    // Android native recorder: restart its recording for a fresh gesture clip.
    final nativeRecorder = _nativeRecorder;
    if (_useNativeRecorder && nativeRecorder != null) {
      nativeRecorder.startRecording();
      return;
    }

    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    final ctrl = cameraNotifier.controller;
    if (ctrl != null) {
      // Restart the gesture feed (records during gestures on iOS) so a retry
      // produces a fresh gesture video too.
      _startGestureFeed();
    }
  }

  static String _guidanceText(String guidance) => switch (guidance) {
    'too_far'   => 'Kindly move closer',
    'too_close' => 'Kindly move further away',
    _           => '',
  };

  static String _lightingText(String guidance) => switch (guidance) {
    'dark'   => 'Move to a brighter area',
    'bright' => 'Too bright. Reduce glare',
    _        => '',
  };

  /// Reports a denied camera permission to onError exactly once (deferred so it
  /// runs after the current build).
  void _reportCameraPermissionDenied(String? message) {
    if (_cameraPermissionReported) return;
    _cameraPermissionReported = true;
    final error = KYCError(
      code: 'camera_permission_denied',
      message: message ??
          'Camera access is required for the liveness check. Please allow camera access and try again.',
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onError?.call(error));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final livenessState = ref.watch(livenessNotifierProvider);
    final cameraState = ref.watch(cameraNotifierProvider);
    final controller =
        ref.read(cameraNotifierProvider.notifier).controller;

    ref.listen<LivenessState>(livenessNotifierProvider, (prev, next) {
      final phaseChanged    = prev?.phase != next.phase;
      final guidanceChanged = prev?.positionGuidance != next.positionGuidance;
      final multiChanged    = prev?.multipleFaces != next.multipleFaces;
      final lightChanged    = prev?.lightingGuidance != next.lightingGuidance;

      // Speak the "only your face" prompt when a second face appears (takes
      // priority over the regular instruction).
      if (multiChanged && next.multipleFaces) {
        _tts.speak(LivenessNotifier.multipleFacesGuidance);
      } else if (lightChanged && next.lightingGuidance != null) {
        // Speak lighting guidance when it first appears.
        _tts.speak(_lightingText(next.lightingGuidance!));
      } else if (phaseChanged && next.instruction.isNotEmpty && !next.multipleFaces) {
        // Speak instruction when phase/challenge changes.
        _tts.speak(next.instruction);
      }

      // Speak position guidance when it first appears (or changes).
      if (guidanceChanged && next.positionGuidance != null && !next.multipleFaces) {
        _tts.speak(_guidanceText(next.positionGuidance!));
      }

      if (phaseChanged) {
        if (next.phase == LivenessPhase.capturing) {
          _handleCapture();
        } else if (next.phase == LivenessPhase.complete &&
            next.selfieBase64 != null) {
          _handleComplete(next.selfieBase64!);
        }
      }
    });

    // "Here's what happens next" — shown before the permission primer, so the
    // selfie camera never opens unannounced.
    if (!_ready) {
      return ReadyPrimer(
        content: readyLiveness,
        onReady: () {
          setState(() => _ready = true);
          _maybePrime(); // now decide: OS prompt, or straight to the camera
        },
      );
    }

    // Camera-access primer — shown before the OS prompt (camera not yet started).
    if (_showPrimer) {
      return CameraPermissionPrimingView(
        message:
            'When prompted, allow camera access to continue your verification.',
        onGrant: () {
          setState(() => _showPrimer = false);
          _init();
        },
      );
    }

    // Camera permission denied — show a dedicated screen + report onError once.
    // `_permissionDenied` covers the Android native-recorder path (no
    // cameraNotifier); `cameraState.isPermissionDenied` covers the iOS/Flutter-
    // camera path where the controller surfaces the denial.
    if (_permissionDenied || cameraState.isPermissionDenied) {
      _reportCameraPermissionDenied(cameraState.error);
      return CameraPermissionView(
        message: cameraState.error ??
            'Camera access is required for the liveness check. Please allow camera access and try again.',
        onOpenSettings: openDeviceAppSettings,
        // iOS: changing the permission can only happen in Settings (which
        // relaunches the app), so an in-place "Try Again" can't succeed — omit it.
        onRetry: Platform.isIOS
            ? null
            : () {
                _cameraPermissionReported = false;
                _init();
              },
      );
    }

    if (livenessState.phase == LivenessPhase.loading) {
      return _LoadingView(error: cameraState.error);
    }

    return _ActiveView(
      previewKey: _previewKey,
      livenessState: livenessState,
      controller: controller,
      nativeTextureId: _nativeTextureId,
      nativePreviewW: _nativePreviewW,
      nativePreviewH: _nativePreviewH,
      isDim: _isDim,
      isBright: _isBright,
      onRetry: livenessState.isFailed ? _retryLiveness : null,
      onSelfieAccepted: _onSelfieAccepted,
      onRetakeSelfie: _retryLiveness,
      isUploadingSelfie: _isUploadingSelfie,
      selfieUploadError: _selfieUploadError,
      selfieRetryInfo: _selfieRetryInfo,
      onDismissUploadError: () => setState(() => _selfieUploadError = null),
    );
  }
}

// ─── TTS service ──────────────────────────────────────────────────────────────

class _TtsService {
  FlutterTts? _tts;
  bool _enabled = true;

  /// Initializes TTS for the spoken liveness instructions. When [enabled] is
  /// false, [speak] becomes a no-op (spoken guidance is off). [language] is a
  /// BCP-47 tag selecting the voice (default 'en-US'). TTS is output only — no
  /// microphone is used.
  Future<void> initialize({bool enabled = true, String language = 'en-US'}) async {
    _enabled = enabled;
    if (!enabled) return;
    _tts = FlutterTts();
    await _tts!.setLanguage(language);
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    await _tts!.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (!_enabled) return;
    await _tts?.stop();
    await _tts?.speak(text);
  }

  /// Stops any in-flight speech without tearing down the engine.
  Future<void> stop() async {
    await _tts?.stop();
  }

  Future<void> dispose() async {
    await _tts?.stop();
    _tts = null;
  }
}

// ─── Loading view ─────────────────────────────────────────────────────────────
//
// Shows the same circle footprint as the camera circle so the layout
// doesn't shift when the camera becomes ready.

class _LoadingView extends StatelessWidget {
  final String? error;

  const _LoadingView({this.error});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.videoOff,
                size: 48, color: MyazaColors.error),
            const SizedBox(height: MyazaSpacing.md),
            Text('Camera unavailable',
                style: text.heading3, textAlign: TextAlign.center),
            const SizedBox(height: MyazaSpacing.sm),
            Text(error!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Setting up…',
          style: text.heading3.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.lg),

        Center(
          child: Container(
            width: MyazaSizing.cameraCircleSize,
            height: MyazaSizing.cameraCircleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary50,
              border: Border.all(color: colors.gray300, width: 2),
            ),
            child: Center(
              child: _PulseLoader(color: colors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Pulse loader ─────────────────────────────────────────────────────────────
//
// Pulsing ring + tinted spinner badge — mirrors the submitting screen's loader
// (submitted_screen.dart). Used by the "Setting up" view and the in-frame selfie
// upload overlay.

class _PulseLoader extends StatelessWidget {
  final Color color;

  const _PulseLoader({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing outer ring.
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1.05, 1.05),
                duration: 1000.ms,
                curve: Curves.easeInOut,
              )
              .fadeOut(begin: 0.8, duration: 1000.ms),
          // Inner tinted circle with spinner.
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: CircularProgressIndicator(
                color: color,
                strokeWidth: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active view ──────────────────────────────────────────────────────────────
//
// Handles all phases except loading: positioning, challenge, passed,
// capturing, complete (selfie review), and failed.

class _ActiveView extends StatelessWidget {
  final GlobalKey previewKey;
  final LivenessState livenessState;
  final CameraController? controller;

  /// Android native CameraX preview texture id (null on iOS / Flutter-camera path).
  final int? nativeTextureId;
  final int nativePreviewW;
  final int nativePreviewH;
  final bool isDim;
  final bool isBright;
  final VoidCallback? onRetry;
  final VoidCallback onSelfieAccepted;
  final VoidCallback onRetakeSelfie;
  final bool isUploadingSelfie;
  final String? selfieUploadError;
  final ({int attempt, int total})? selfieRetryInfo;
  final VoidCallback onDismissUploadError;

  const _ActiveView({
    required this.previewKey,
    required this.livenessState,
    required this.controller,
    required this.nativeTextureId,
    required this.nativePreviewW,
    required this.nativePreviewH,
    required this.isDim,
    required this.isBright,
    required this.onSelfieAccepted,
    required this.onRetakeSelfie,
    required this.isUploadingSelfie,
    required this.selfieUploadError,
    required this.selfieRetryInfo,
    required this.onDismissUploadError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final phase = livenessState.phase;
    final isFailed = phase == LivenessPhase.failed;

    // ── Selfie review ─────────────────────────────────────────────────────────
    if (phase == LivenessPhase.complete && livenessState.selfieBase64 != null) {
      return _SelfieReviewView(
        selfieBase64: livenessState.selfieBase64!,
        onRetake: onRetakeSelfie,
        onContinue: onSelfieAccepted,
        isUploading: isUploadingSelfie,
        uploadError: selfieUploadError,
        retryInfo: selfieRetryInfo,
        onDismissError: onDismissUploadError,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Instruction (hidden when failed — error text replaces it) ─────────
        if (!isFailed) ...[
          _InstructionBanner(
            phase: phase,
            instruction: livenessState.instruction,
            faceDetected: livenessState.faceDetected,
            positionGuidance: livenessState.positionGuidance,
            wrongGesture: livenessState.wrongGesture,
            multipleFaces: livenessState.multipleFaces,
            lightingGuidance: livenessState.lightingGuidance,
          ),
          const SizedBox(height: MyazaSpacing.sm),
          // ── Lighting warning (too dark / too bright; non-blocking amber) ────
          _LightingWarningBanner(isDim: isDim, isBright: isBright),
          SizedBox(
            height: (isDim || isBright) ? MyazaSpacing.sm : MyazaSpacing.md,
          ),
        ] else
          const SizedBox(height: MyazaSpacing.sm),

        // ── Camera circle ─────────────────────────────────────────────────────
        Center(
          child: _CameraCircle(
            key: previewKey,
            controller: controller,
            nativeTextureId: nativeTextureId,
            nativePreviewW: nativePreviewW,
            nativePreviewH: nativePreviewH,
            phase: phase,
            faceDetected: livenessState.faceDetected,
            flashReadyProgress: livenessState.flashReadyProgress,
            hasWarning: livenessState.wrongGesture ||
                livenessState.positionGuidance != null ||
                livenessState.multipleFaces ||
                livenessState.lightingGuidance != null,
          ),
        ),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Step indicators ───────────────────────────────────────────────────
        if (livenessState.totalCount > 0)
          _StepIndicators(
            completedCount: livenessState.completedCount,
            totalCount: livenessState.totalCount,
            phase: phase,
          ),

        // ── Failed: error text + retry button ─────────────────────────────────
        if (isFailed) ...[
          const SizedBox(height: MyazaSpacing.md),
          Text(
            "Time's up. Let's try again.",
            style: context.myazaText.bodyMedium.copyWith(
              color: MyazaColors.error,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MyazaSpacing.lg),
          MyazaButton(label: 'Try Again', onPressed: onRetry),
        ],

        // ── Active: liveness avatar ───────────────────────────────────────────
        if (!isFailed) ...[
          const SizedBox(height: MyazaSpacing.xl),
          Center(
            child: LivenessAvatar(
              activeChallenge: livenessState.activeChallenge,
              phase: phase,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Selfie review view ───────────────────────────────────────────────────────
//
// Shows the captured selfie in a circle so the user can retake or continue.

class _SelfieReviewView extends StatelessWidget {
  final String selfieBase64;
  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final bool isUploading;
  final String? uploadError;
  final ({int attempt, int total})? retryInfo;
  final VoidCallback onDismissError;

  const _SelfieReviewView({
    required this.selfieBase64,
    required this.onRetake,
    required this.onContinue,
    required this.isUploading,
    required this.uploadError,
    required this.retryInfo,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(selfieBase64);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Selfie circle (with in-frame uploading overlay) ───────────────────
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: MyazaSizing.cameraCircleSize,
            height: MyazaSizing.cameraCircleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.myazaColors.primary200, width: 3),
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // No mirror Transform: the selfie JPEG is already baked
                  // selfie-mirrored (iOS via processSelfieFrame(mirror:true),
                  // Android via the native still's postScale flip) — and that's
                  // exactly the bytes we upload, so display them as-is to match.
                  Image.memory(imageBytes, fit: BoxFit.cover),
                  // Uploading loader rendered INSIDE the selfie preview frame
                  // (replaces the old standalone "Uploading…" pill). Mirrors the
                  // submitting screen's pulse-ring + spinner loader.
                  if (isUploading)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      child: Center(
                        child: _PulseLoader(color: context.myazaColors.primary),
                      ),
                    ).animate().fadeIn(duration: 200.ms),
                ],
              ),
            ),
          ),
        )
            .animate()
            .scale(
              begin: const Offset(0.85, 0.85),
              end: const Offset(1.0, 1.0),
              duration: 400.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 300.ms),

        if (retryInfo != null && isUploading) ...[
          const SizedBox(height: MyazaSpacing.md),
          Text(
            'Upload failed — retrying (${retryInfo!.attempt}/${retryInfo!.total})…',
            style: context.myazaText.bodySmall.copyWith(
              color: const Color(0xFF92400E), // amber-800
            ),
            textAlign: TextAlign.center,
          ),
        ],

        if (uploadError != null) ...[
          const SizedBox(height: MyazaSpacing.lg),
          MyazaAlert(
            variant: MyazaAlertVariant.error,
            title: 'Upload failed',
            message: uploadError!,
            onDismiss: onDismissError,
          )
              .animate()
              .fadeIn(duration: 250.ms)
              .slideY(begin: -0.2, end: 0, duration: 250.ms),
        ],

        const SizedBox(height: MyazaSpacing.xl),

        // ── Retake / Continue ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: MyazaButton.outline(
                label: 'Retake',
                onPressed: isUploading ? null : onRetake,
                leadingIcon: const Icon(LucideIcons.rotateCcw),
              ),
            ),
            const SizedBox(width: MyazaSpacing.md),
            Expanded(
              child: MyazaButton(
                label: uploadError != null ? 'Try Again' : 'Continue',
                onPressed: isUploading ? null : onContinue,
                leadingIcon: Icon(
                  uploadError != null
                      ? LucideIcons.rotateCcw
                      : LucideIcons.check,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Instruction banner ───────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  final LivenessPhase phase;
  final String instruction;
  final bool faceDetected;

  /// 'too_far', 'too_close', or null. When set, overrides [instruction].
  final String? positionGuidance;

  /// True when the user is performing a different gesture than requested.
  final bool wrongGesture;

  /// True when more than one face is in frame (paused).
  final bool multipleFaces;

  /// 'dark', 'bright', or null — poor-lighting guidance.
  final String? lightingGuidance;

  const _InstructionBanner({
    required this.phase,
    required this.instruction,
    required this.faceDetected,
    this.positionGuidance,
    this.wrongGesture = false,
    this.multipleFaces = false,
    this.lightingGuidance,
  });

  @override
  Widget build(BuildContext context) {
    final showNoFace = !faceDetected &&
        phase != LivenessPhase.loading &&
        phase != LivenessPhase.complete &&
        phase != LivenessPhase.failed;

    final hasPositionWarning = positionGuidance != null && faceDetected;
    final isChallenge        = phase == LivenessPhase.challenge;
    final isChallengePassed  = phase == LivenessPhase.challengePassed;
    final hasWrongGesture    = wrongGesture && isChallenge && faceDetected;

    final colors = context.myazaColors;
    final text   = context.myazaText;

    // Priority: no-face > multiple faces > lighting > position > wrong > passed
    final String displayText;
    final Color  textColor;

    if (showNoFace) {
      displayText = 'No face detected';
      textColor   = MyazaColors.error;
    } else if (multipleFaces) {
      displayText = LivenessNotifier.multipleFacesGuidance;
      textColor   = MyazaColors.error;
    } else if (lightingGuidance != null) {
      displayText = lightingGuidance == 'dark'
          ? 'Move to a brighter area'
          : 'Too bright — reduce glare';
      textColor = MyazaColors.error;
    } else if (hasPositionWarning) {
      displayText = positionGuidance == 'too_far'
          ? 'Kindly move closer'
          : 'Kindly move further away';
      textColor = MyazaColors.error;
    } else if (hasWrongGesture) {
      displayText = 'Wrong gesture';
      textColor   = MyazaColors.error;
    } else if (isChallengePassed) {
      displayText = instruction;
      textColor   = MyazaColors.success;
    } else if (isChallenge) {
      displayText = instruction;
      textColor   = MyazaColors.secondary;
    } else {
      displayText = instruction;
      textColor   = colors.textDark;
    }

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            displayText,
            key: ValueKey(displayText),
            style: text.heading3.copyWith(color: textColor),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── Camera circle ────────────────────────────────────────────────────────────

class _CameraCircle extends StatelessWidget {
  final CameraController? controller;

  /// Android native CameraX preview texture id (null on the Flutter-camera path).
  final int? nativeTextureId;
  final int nativePreviewW;
  final int nativePreviewH;
  final LivenessPhase phase;
  final bool faceDetected;

  /// Wrong gesture or wrong distance — turns the ring red (mirrors the web SDK).
  final bool hasWarning;

  /// Flash-only pre-flash dwell, 0..1. Draws a filling ring so the "hold still"
  /// moment before the screen flashes is visible, not a silent pause.
  final double flashReadyProgress;

  const _CameraCircle({
    super.key,
    required this.controller,
    required this.phase,
    required this.faceDetected,
    this.flashReadyProgress = 0,
    this.nativeTextureId,
    this.nativePreviewW = 0,
    this.nativePreviewH = 0,
    this.hasWarning = false,
  });

  bool get _showOval =>
      phase == LivenessPhase.positioning ||
      phase == LivenessPhase.challenge ||
      phase == LivenessPhase.challengePassed;

  Color _borderColor(MyazaColorScheme colors) {
    if (!faceDetected &&
        phase != LivenessPhase.loading &&
        phase != LivenessPhase.complete &&
        phase != LivenessPhase.failed) {
      return MyazaColors.error;
    }
    // Red ring for a wrong gesture / wrong distance during an active challenge.
    if (hasWarning &&
        (phase == LivenessPhase.challenge ||
            phase == LivenessPhase.positioning)) {
      return MyazaColors.error;
    }
    return switch (phase) {
      LivenessPhase.loading                                  => colors.gray300,
      LivenessPhase.failed                                   => MyazaColors.error,
      LivenessPhase.challengePassed ||
      LivenessPhase.capturing      ||
      LivenessPhase.complete                                 => MyazaColors.success,
      _                                                      => colors.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors      = context.myazaColors;
    final borderColor = _borderColor(colors);
    final hasNative   = nativeTextureId != null && nativeTextureId! >= 0;
    final isReady     = hasNative ||
        (controller != null && controller!.value.isInitialized);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: MyazaSizing.cameraCircleSize + 6,
      height: MyazaSizing.cameraCircleSize + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox.square(
          dimension: MyazaSizing.cameraCircleSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasNative)
                NativeCameraPreview(
                  textureId: nativeTextureId!,
                  bufferWidth: nativePreviewW,
                  bufferHeight: nativePreviewH,
                )
              else if (isReady)
                _CameraPreviewFill(controller: controller!)
              else
                _CameraPlaceholder(phase: phase),

              // Dashed oval face guide
              if (isReady && _showOval)
                CustomPaint(
                  painter: _DashedOvalPainter(
                    color: faceDetected
                        ? MyazaColors.success
                        : colors.gray300,
                  ),
                ),

              // Flash-only "getting ready" ring — a solid arc that sweeps as the
              // pre-flash dwell completes, so the hold reads as progress toward
              // the flash rather than a stall.
              if (isReady && flashReadyProgress > 0)
                CustomPaint(
                  painter: _ReadyRingPainter(
                    progress: flashReadyProgress,
                    color: MyazaColors.success,
                  ),
                ),

              // Soft green wash over the whole circle when a challenge passes
              // (mirrors the web SDK's bg-success/20 flash). Sits behind the
              // checkmark badge below.
              if (phase == LivenessPhase.challengePassed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MyazaColors.success.withValues(alpha: 0.20),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 200.ms, curve: Curves.easeOut),

              // "Got it!" white wash during auto-capture.
              if (phase == LivenessPhase.capturing)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                  child: Center(
                    child: Text(
                      'Got it!',
                      style: context.myazaText.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 200.ms, curve: Curves.easeOut),

              // Animated checkmark badge when challenge passes
              if (phase == LivenessPhase.challengePassed)
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: MyazaColors.success,
                    ),
                    child: const Icon(
                      LucideIcons.check,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.4, 0.4),
                      end: const Offset(1.0, 1.0),
                      duration: 450.ms,
                      curve: Curves.easeOutBack,
                    )
                    .fadeIn(duration: 200.ms, curve: Curves.easeOut),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover-fit camera preview inside the circle.
class _CameraPreviewFill extends StatelessWidget {
  final CameraController controller;

  const _CameraPreviewFill({required this.controller});

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return Container(color: context.myazaColors.primary50);
    }

    // previewSize is in landscape (width > height on portrait devices).
    // Swap to get correct portrait display dimensions.
    final double w = previewSize.height;
    final double h = previewSize.width;

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: w,
        height: h,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  final LivenessPhase phase;

  const _CameraPlaceholder({required this.phase});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    return Container(
      color: colors.primary50,
      child: Center(
        child: phase == LivenessPhase.complete
            ? const Icon(LucideIcons.circleCheck,
                    size: 56, color: MyazaColors.success)
                .animate()
                .scale(
                  begin: const Offset(0.3, 0.3),
                  end: const Offset(1, 1),
                  duration: 400.ms,
                  curve: Curves.elasticOut,
                )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: colors.primary,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: MyazaSpacing.sm),
                  Text(
                    'Loading…',
                    style: text.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Flash overlay ────────────────────────────────────────────────────────────

/// Paints the fullscreen flash colour with a circular hole at [hole] (the real
/// preview's screen rect), so the live preview shows straight through — fixed in
/// place, never a second preview that pops in at a different spot and shakes.
///
/// The hole is a small fraction of the screen, so it barely dents the emitted
/// light; and because that region looks identical in the neutral and lit frames
/// it cancels in the reflection measurement rather than skewing it.
class _FlashHolePainter extends CustomPainter {
  final Color color;
  final Rect? hole;

  const _FlashHolePainter({required this.color, required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final h = hole;
    if (h == null) {
      canvas.drawRect(bounds, Paint()..color = color);
      return;
    }
    // saveLayer + BlendMode.clear cuts a real transparent hole so whatever is
    // BELOW the overlay (the live preview) is revealed, not just painted over.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = color);
    canvas.drawCircle(
      h.center,
      h.width / 2,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlashHolePainter old) =>
      old.color != color || old.hole != hole;
}

// ─── Flash-ready progress ring ────────────────────────────────────────────────

/// A solid arc sweeping clockwise from the top as the pre-flash dwell fills.
/// Sits just inside the circle's edge so it reads as the ring "charging".
class _ReadyRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  const _ReadyRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Inset by the stroke so the arc sits fully inside the clip.
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawArc(
      rect,
      -math.pi / 2, // 12 o'clock
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ReadyRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── Dashed oval face guide ───────────────────────────────────────────────────

class _DashedOvalPainter extends CustomPainter {
  final Color color;

  const _DashedOvalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Oval inset 15 % horizontally and 8 % vertically to frame the face
    final rect = Rect.fromLTWH(
      size.width * 0.15,
      size.height * 0.08,
      size.width * 0.70,
      size.height * 0.84,
    );

    final path = Path()..addOval(rect);
    _drawDashed(canvas, path, paint);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const double dashLen = 8.0;
    const double gapLen = 6.0;

    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < metric.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) {
          canvas.drawPath(
            metric.extractPath(dist, math.min(dist + len, metric.length)),
            paint,
          );
        }
        dist += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOvalPainter old) => old.color != color;
}

// ─── Step indicators ──────────────────────────────────────────────────────────
//
// Numbered circles connected by a line — matches the web SDK design.
// Completed = green circle with checkmark
// Active    = primary-outlined circle with number
// Pending   = primary50 filled circle with gray number

class _StepIndicators extends StatelessWidget {
  final int completedCount;
  final int totalCount;
  final LivenessPhase phase;

  const _StepIndicators({
    required this.completedCount,
    required this.totalCount,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < totalCount; i++) ...[
          if (i > 0)
            _StepConnector(filled: i <= completedCount),
          _StepDot(
            number: i + 1,
            isCompleted: i < completedCount,
            isActive: i == completedCount &&
                (phase == LivenessPhase.challenge ||
                    phase == LivenessPhase.positioning),
          ),
        ],
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool filled;

  const _StepConnector({required this.filled});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: filled ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      builder: (context, animatedFill, _) {
        return Stack(
          children: [
            Container(width: 32, height: 2, color: colors.gray300),
            ClipRect(
              child: SizedBox(
                width: 32 * animatedFill,
                height: 2,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: 32,
                  child: Container(
                    width: 32,
                    height: 2,
                    color: MyazaColors.success,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StepDot extends StatelessWidget {
  final int number;
  final bool isCompleted;
  final bool isActive;

  const _StepDot({
    required this.number,
    required this.isCompleted,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    Color bg;
    Color border;
    Widget child;

    if (isCompleted) {
      bg = MyazaColors.success;
      border = MyazaColors.success;
      child = const Icon(LucideIcons.check, size: 14, color: Colors.white);
    } else if (isActive) {
      bg = Colors.transparent;
      border = MyazaColors.success;
      child = Text(
        '$number',
        style: text.bodySmall.copyWith(
          color: MyazaColors.success,
          fontWeight: FontWeight.w700,
        ),
      );
    } else {
      bg = colors.primary50;
      border = colors.primary200;
      child = Text(
        '$number',
        style: text.bodySmall.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: KeyedSubtree(
            key: ValueKey(isCompleted ? 'done' : isActive ? 'active' : 'pending'),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Lighting warning banner ─────────────────────────────────────────────────
//
// Shown when the brightness sampler detects poor light (too dark OR too bright)
// for 2 consecutive readings (~1.6 s). Non-blocking informational banner; the
// state machine separately gates challenge start while lighting is poor. Matches
// the web SDK's amber alert style.

class _LightingWarningBanner extends StatelessWidget {
  final bool isDim;
  final bool isBright;

  const _LightingWarningBanner({required this.isDim, required this.isBright});

  @override
  Widget build(BuildContext context) {
    final show = isDim || isBright;
    final message = isBright
        ? 'Too bright — reduce glare or move away from direct light for better detection.'
        : 'It looks dark here. Move to a brighter area or near a light source for better detection.';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: show
          ? Container(
              key: ValueKey(isBright ? 'bright' : 'dim'),
              padding: const EdgeInsets.symmetric(
                horizontal: MyazaSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),   // amber-50
                borderRadius: BorderRadius.circular(MyazaRadius.sm),
                border: Border.all(color: const Color(0xFFFDE68A)), // amber-200
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.lightbulb,
                    size: 16,
                    color: Color(0xFF92400E), // amber-800
                  ),
                  const SizedBox(width: MyazaSpacing.sm),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(key: ValueKey('ok')),
    );
  }
}

// ─── Brightness sampler ───────────────────────────────────────────────────────
//
// Mirrors useLightLevel.ts from the web SDK:
//   - Samples luminance every 800 ms (after a 1.5 s warmup)
//   - Requires 2 consecutive dark readings before flagging as dim
//   - Uses ITU-R BT.601 luminance: 0.299·R + 0.587·G + 0.114·B
//   - Threshold: mean luminance < 62 (out of 255)
//
// On Android the camera delivers NV21 frames — the Y (luminance) plane is
// sampled directly. On iOS frames are BGRA8888 — RGB → luma conversion used.

enum _LightLevel { ok, dark, bright }

class _BrightnessSampler {
  static const double dimThreshold    = 62.0;  // 0–255 — below = too dark
  static const double brightThreshold = 200.0; // 0–255 — above = overexposed
  static const int    sampleInterval  = 800;   // ms
  static const int    warmupMs        = 1500;  // ms before first sample
  static const int    confirmCount    = 2;     // consecutive readings needed

  int? _startMs;
  int? _lastSampleMs;
  // Signed streak: negative = consecutive dark readings, positive = bright.
  int  _streak = 0;

  void reset() {
    _startMs       = null;
    _lastSampleMs  = null;
    _streak        = 0;
  }

  /// Classifies the lighting as ok / dark / bright if it is time to sample, or
  /// null if the warmup / throttle interval has not elapsed. Requires
  /// [confirmCount] consecutive out-of-range readings before flagging, so a
  /// single bad frame (e.g. a hand briefly over the lens) is ignored.
  _LightLevel? sample(CameraImage image) {
    if (!_shouldSampleNow()) return null;
    final luma = Platform.isAndroid ? _sampleNv21(image) : _sampleBgra(image);
    return _classify(luma);
  }

  /// Native (Android) path: classify from a mean luma (0–255) already computed
  /// natively, since the raw camera frame isn't available in Dart there.
  _LightLevel? sampleLuma(double luma) {
    if (!_shouldSampleNow()) return null;
    return _classify(luma);
  }

  bool _shouldSampleNow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _startMs ??= now;
    if (now - _startMs! < warmupMs) return false;
    if (_lastSampleMs != null && now - _lastSampleMs! < sampleInterval) {
      return false;
    }
    _lastSampleMs = now;
    return true;
  }

  _LightLevel _classify(double luma) {
    if (luma < dimThreshold) {
      _streak = _streak <= 0 ? _streak - 1 : -1;
    } else if (luma > brightThreshold) {
      _streak = _streak >= 0 ? _streak + 1 : 1;
    } else {
      _streak = 0;
    }

    if (_streak <= -confirmCount) return _LightLevel.dark;
    if (_streak >= confirmCount) return _LightLevel.bright;
    return _LightLevel.ok;
  }

  // ── Platform-specific luminance extraction ─────────────────────────────────

  /// NV21: the first plane is the Y (luma) channel, one byte per pixel.
  double _sampleNv21(CameraImage image) {
    try {
      final plane  = image.planes[0];
      final bytes  = plane.bytes;
      final stride = plane.bytesPerRow;
      final w = image.width;
      final h = image.height;

      // Sample a 16×12 grid from the central 50 % of the frame.
      final x0 = w ~/ 4;  final x1 = w * 3 ~/ 4;
      final y0 = h ~/ 4;  final y1 = h * 3 ~/ 4;
      final sx = ((x1 - x0) ~/ 16).clamp(1, 999);
      final sy = ((y1 - y0) ~/ 12).clamp(1, 999);

      double total = 0; int count = 0;
      for (int y = y0; y < y1; y += sy) {
        final row = y * stride;
        for (int x = x0; x < x1; x += sx) {
          if (row + x < bytes.length) {
            total += bytes[row + x] & 0xFF;
            count++;
          }
        }
      }
      return count > 0 ? total / count : dimThreshold + 1;
    } catch (_) {
      return dimThreshold + 1;
    }
  }

  /// BGRA8888: interleaved B, G, R, A — 4 bytes per pixel.
  double _sampleBgra(CameraImage image) {
    try {
      final plane      = image.planes[0];
      final bytes      = plane.bytes;
      final bpr        = plane.bytesPerRow;
      final bpp        = (bpr ~/ image.width).clamp(1, 8);
      final w = image.width;
      final h = image.height;

      final x0 = w ~/ 4;  final x1 = w * 3 ~/ 4;
      final y0 = h ~/ 4;  final y1 = h * 3 ~/ 4;
      final sx = ((x1 - x0) ~/ 16).clamp(1, 999);
      final sy = ((y1 - y0) ~/ 12).clamp(1, 999);

      double total = 0; int count = 0;
      for (int y = y0; y < y1; y += sy) {
        final row = y * bpr;
        for (int x = x0; x < x1; x += sx) {
          final p = row + x * bpp;
          if (p + 2 < bytes.length) {
            final b = bytes[p]     & 0xFF;
            final g = bytes[p + 1] & 0xFF;
            final r = bytes[p + 2] & 0xFF;
            total += 0.299 * r + 0.587 * g + 0.114 * b;
            count++;
          }
        }
      }
      return count > 0 ? total / count : dimThreshold + 1;
    } catch (_) {
      return dimThreshold + 1;
    }
  }
}
