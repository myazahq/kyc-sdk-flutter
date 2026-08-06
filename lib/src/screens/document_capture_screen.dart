import 'dart:io' show Platform;
import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/capture_config.dart';
import '../config/document_guide.dart';
import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/camera_provider.dart';
import '../providers/step_order.dart' show effectiveCountry;
import '../services/document_detection.dart';
import '../services/document_framing_gate.dart';
import '../services/document_identity.dart';
import '../services/document_text_gate.dart';
import '../services/mrz_extract.dart';
import '../services/native_document_camera.dart';
import '../services/text_recognition.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../services/image_service.dart';
import '../services/kyc_error_mapper.dart';
import '../services/media_compress_service.dart';
import '../services/retry.dart';
import '../utils/permissions.dart';
import '../widgets/document_review.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/camera_permission_priming_view.dart';
import '../widgets/ready_primer.dart';
import '../widgets/ready_primer_content.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/document_cropper.dart';
import '../widgets/document_viewfinder.dart';
import '../widgets/myaza_button.dart';

// ─── Scan phase ───────────────────────────────────────────────────────────────
//
// cameraFront   → camera open, scanning front side
// frontPreview  → front captured; user reviews before scanning back
// cameraBack    → camera open, scanning back side (two-sided IDs only)
// review        → both (or all) sides captured; upload runs from Continue

enum _ScanPhase { cameraFront, frontPreview, cameraBack, review }

/// Thrown to skip a side clip that recorded no frames. Caught by the same
/// best-effort handler that already tolerates a failed video upload.
class _EmptyClip implements Exception {
  const _EmptyClip();
}

// ─── Document capture screen ──────────────────────────────────────────────────

class DocumentCaptureScreen extends ConsumerStatefulWidget {
  /// Fires for technical errors raised on this screen (camera permission
  /// denied, document upload failed after retries).
  final void Function(KYCError error)? onError;

  const DocumentCaptureScreen({super.key, this.onError});

  @override
  ConsumerState<DocumentCaptureScreen> createState() =>
      _DocumentCaptureScreenState();
}

class _DocumentCaptureScreenState
    extends ConsumerState<DocumentCaptureScreen>
    with WidgetsBindingObserver {
  _ScanPhase _phase = _ScanPhase.cameraFront;

  // True while the camera is (re)initialising — ignores the inactive→resumed
  // bounce from the OS permission prompt (the in-flight init handles it).
  bool _initializing = false;
  // Set when the explicit camera-permission check fails.
  bool _permissionDenied = false;
  // Show the "Allow camera access" primer before the OS prompt (Stripe-style),
  // unless the camera is already granted. The camera (and therefore the OS
  // prompt) only starts once the user taps "Grant access".
  /// Whether the user has acknowledged the "here's what happens next"
  /// screen. Gates the camera so it never opens unannounced.
  bool _ready = false;
  bool _showPrimer = false;

  // Locally held captures — only uploaded + committed to kycProvider on Continue.
  Uint8List? _frontBytes;
  Uint8List? _backBytes;

  // Locally held video recording file paths — captured during the camera
  // phase and compressed + uploaded alongside the still images on Continue.
  // Best-effort: if the device or permissions don't support recording, the
  // still image still proceeds. Paths (not bytes) so they can be handed to
  // VideoCompress before reading the smaller bytes for upload.
  String? _frontVideoPath;
  String? _backVideoPath;

  bool _isCapturing = false;

  // Android's native CameraX camera (see NativeDocumentCamera). Null on iOS and
  // on the Android fallback, where the Flutter camera plugin drives the feed.
  NativeDocumentCamera? _nativeCamera;
  int? _nativeTextureId;
  int _nativePreviewW = 0;
  int _nativePreviewH = 0;

  // Set when the native camera failed to start, so the fallback sticks for the
  // rest of the screen instead of retrying native on every side/retake.
  bool _nativeFailed = false;

  // Latest identity verdict from text recognition (iOS path). Null means it
  // could not be established this frame — never a reason to block a capture.
  DocumentIdentity? _identity;

  // The viewfinder's actual laid-out size, recorded during build. The crop maps
  // the guide rect back into the still against exactly this box, and in
  // full-screen mode it is the whole display rather than anything derivable
  // from a constant — so it is measured, not assumed.
  Size? _viewfinderSize;

  // Mirrors what we last told the provider, so the flag is only pushed on a
  // real change (and never from inside build).
  bool _immersiveWanted = false;

  // Torch state + whether this camera has a flash unit at all.
  bool _torchOn = false;
  bool _hasTorch = false;

  // True while the side clip is being restarted — auto-capture must not fire
  // into that window (see _resumeCaptureForSide).
  bool _restartingClip = false;

  // Auto-capture: native detector + the framing/stability policy.
  final _detector = DocumentDetectionService();
  late final DocumentFramingGate _gate = DocumentFramingGate(
    // Shape is what stops auto-capture firing on a book or a receipt, so the
    // gate is built per ID type: a card is 1.586, a passport page 1.42. The
    // card aspect is the fallback — every document ID uses one of the two, and
    // the guide the user is aiming at already shows which.
    expectedAspect: () {
      final idType = ref.read(kYCNotifierProvider).selectedIdType;
      return idType == null ? kCardGuideAspect : documentGuideAspect(idType);
    }(),
  );
  // Android has no rectangle detector, so it auto-captures off on-device text
  // recognition instead (see _detectFrameText / DocumentTextGate).
  final _textRecognizer = TextRecognitionService();
  final _textGate = DocumentTextGate();

  DocumentFraming _framing = DocumentFraming.none;
  DocumentHint _hint = DocumentHint.searching;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0); // still-photo in progress
  bool _isUploading = false; // upload in progress

  String? _uploadError;
  ({int attempt, int total})? _uploadRetryInfo;

  // Ensures the camera_permission_denied error is reported to onError once.
  bool _cameraPermissionReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrime());
  }

  /// True while a capture phase is on screen — the phases that need the camera.
  bool get _inCameraPhase =>
      _phase == _ScanPhase.cameraFront || _phase == _ScanPhase.cameraBack;

  /// Show the "Allow camera access" primer before requesting permission, unless
  /// the camera is already granted (in which case we open it straight away).
  ///
  /// Re-invoked when the user acknowledges the ready screen: opening the camera
  /// behind that screen is precisely what it exists to prevent, so while it is
  /// up this is a no-op.
  Future<void> _maybePrime() async {
    if (!_ready && _inCameraPhase) return;
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
    // The plugin controller is released by the camera provider's onDispose; the
    // native camera is ours to tear down.
    final native = _nativeCamera;
    _nativeCamera = null;
    if (native != null) unawaited(native.dispose());
    super.dispose();
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────
  //
  // The camera is released when the app is backgrounded (e.g. leaving to
  // Settings to change the camera permission, or while the OS permission prompt
  // is up). On return the old CameraController is dead, so the viewfinder would
  // freeze — re-initialise it on resume, but only while a live camera phase is
  // showing (preview/review render static images).

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || state != AppLifecycleState.resumed) return;
    // iOS only — see LivenessScreen. On Android nothing is re-initialised on
    // resume: the native camera holds its own CameraX session, which reopens the
    // device by itself once it's free again (same as the native liveness
    // recorder), and on the plugin fallback a manual reinit races CameraX's
    // video recorder teardown (fatal "onConfigured in STOPPING state").
    if (!Platform.isIOS) return;
    // A pre-camera screen is up — restoring here would open the camera behind
    // it, which is what those screens exist to prevent. See LivenessScreen.
    if (!_ready || _showPrimer) return;
    if (_initializing) return;
    if (_phase == _ScanPhase.cameraFront || _phase == _ScanPhase.cameraBack) {
      _restartCamera();
    }
  }

  // ── Camera lifecycle ───────────────────────────────────────────────────────

  Future<void> _init() => _restartCamera();

  Future<void> _restartCamera() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    // Start the settle window here, not only after a capture: on the FIRST
    // camera open there is no previous shot to reset from, and an unset window
    // would leave auto-capture disarmed forever.
    _armedAt = DateTime.now();
    try {
      // Android: explicit permission gate before opening the camera. iOS is
      // left to the camera controller's own denial signal (and avoids needing
      // permission_handler Podfile macros).
      if (Platform.isAndroid) {
        final granted = await requestCameraPermission();
        if (!mounted) return;
        if (!granted) {
          _reportCameraPermissionDenied(null);
          setState(() => _permissionDenied = true);
          return;
        }
        if (_permissionDenied) setState(() => _permissionDenied = false);

        // The native camera is Android's normal path; the plugin below is the
        // fallback if it can't start.
        if (!_nativeFailed && await _startNativeCamera()) return;
      }

      await ref.read(cameraNotifierProvider.notifier).initialize(
        direction: CameraLensDirection.back,
        // Kept high (not medium) so the OCR still stays sharp — the document
        // video is shrunk by VideoCompress at encode time instead.
        resolution: CaptureConfig.documentResolution,
      );
      if (!mounted) return;
      setState(() =>
          _hasTorch = ref.read(cameraNotifierProvider.notifier).hasTorch);
      await _startVideoRecording();
    } finally {
      _initializing = false;
    }
  }

  /// Starts the Android native camera + its first side clip. Returns false when
  /// it couldn't start, which latches [_nativeFailed] so the caller falls back
  /// to the Flutter camera plugin for the rest of the screen.
  Future<bool> _startNativeCamera() async {
    final camera = NativeDocumentCamera();
    try {
      final textureId = await camera.start(onText: _onNativeText);
      if (!mounted) {
        unawaited(camera.dispose());
        return true; // screen is gone; nothing to fall back to
      }
      if (textureId < 0) {
        // Bound without producing a texture — nothing to render, so fall back
        // rather than showing a dead preview.
        unawaited(camera.dispose());
        _nativeFailed = true;
        return false;
      }
      await camera.startRecording();
      if (!mounted) {
        unawaited(camera.dispose());
        return true;
      }
      final hasTorch = await camera.hasTorch();
      if (!mounted) {
        unawaited(camera.dispose());
        return true;
      }
      setState(() {
        _hasTorch = hasTorch;
        _nativeCamera = camera;
        _nativeTextureId = textureId;
        _nativePreviewW = camera.previewWidth;
        _nativePreviewH = camera.previewHeight;
      });
      return true;
    } catch (_) {
      unawaited(camera.dispose());
      _nativeFailed = true;
      return false;
    }
  }

  /// Tells the shell whether the full-bleed camera is on screen. Deferred to
  /// after the frame because it is decided during build, and a provider write
  /// mid-build would rebuild the tree underneath us.
  void _syncImmersive(bool wanted) {
    if (_immersiveWanted == wanted) return;
    _immersiveWanted = wanted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(kYCNotifierProvider.notifier).setImmersiveCapture(wanted);
    });
  }

  /// Toggles the torch on whichever camera is driving the feed. Best-effort:
  /// a device that refuses simply stays dark.
  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    setState(() => _torchOn = next);
    final native = _nativeCamera;
    if (native != null) {
      await native.setTorch(next);
    } else {
      await ref.read(cameraNotifierProvider.notifier).setTorch(next);
    }
  }

  /// Readies the camera for the next side (or a retake).
  ///
  /// On the native path the session stays up and only the clip restarts — that
  /// is what removes the visible camera reload between front and back, which a
  /// full re-initialisation used to cost on every side change.
  Future<void> _resumeCaptureForSide() async {
    final native = _nativeCamera;
    if (native == null) {
      await _restartCamera();
      return;
    }
    // Hold auto-capture off until the new clip is live. Without this the gate
    // can fire in the gap below and stop a clip that has not recorded a single
    // frame — which is how a fast retake produced an empty side video.
    _restartingClip = true;
    try {
      // A clip may still be open if the user backed out of a side without
      // capturing; stopping first is a no-op when there isn't one.
      await native.stopRecording();
      if (!mounted) return;
      await native.startRecording();
    } finally {
      _restartingClip = false;
    }
  }

  /// Best-effort start: records a side-specific MP4 capturing how the user
  /// presented the document. If recording fails (e.g. unsupported device),
  /// the still capture flow still works.
  Future<void> _startVideoRecording() async {
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    if (cameraNotifier.isRecordingVideo) return;
    // Frames ride the RECORDING's stream — the camera can't serve a separate
    // image stream while recording, and the side video is not optional.
    await cameraNotifier.startVideoRecording(onImage: _onDetectionFrame);
  }

  // ── Auto-capture ───────────────────────────────────────────────────────────
  //
  // Detection is an accelerator, never the only route: the manual shutter stays
  // live. iOS auto-captures off Apple Vision's rectangle detector; Android off
  // on-device text recognition (ML Kit) via the text gate — a document is
  // text-dense, and a valid MRZ is an even stronger signal. If a platform can't
  // detect, nothing below fires and the manual flow is exactly as it was.

  void _onDetectionFrame(CameraImage image) {
    if (!mounted || _isCapturing || _isUploading) return;
    if (_phase != _ScanPhase.cameraFront && _phase != _ScanPhase.cameraBack) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastDetect) < const Duration(milliseconds: 250)) return;
    _lastDetect = now;
    // iOS: Apple Vision rectangle detector. Android: no rectangle detector in ML
    // Kit, so auto-capture rides on-device TEXT recognition instead — a KYC
    // document is text-dense, and a check-digit-valid MRZ is an even stronger
    // "framed & readable" signal (see _detectFrameText).
    if (Platform.isAndroid) {
      if (_textRecognizer.isBusy) return;
      _detectFrameText(image);
    } else {
      // iOS runs BOTH checks, so a capture clears the same bar as Android:
      // Apple Vision's rectangle detector answers "is it framed like a
      // document", and text recognition answers "is it the RIGHT document" —
      // which geometry alone cannot, since an aspect ratio cannot tell a
      // passport from a driver's licence. It also reads the MRZ ahead of the
      // shutter, so the chip step needs no second scan here either.
      if (!_textRecognizer.isBusy) unawaited(_updateIdentity(image));
      if (_detector.isUnsupported || _detector.isBusy) return;
      _detectFrame(image);
    }
  }

  /// iOS: recognize text purely to establish identity (and bank the MRZ). The
  /// verdict is consumed by [_detectFrame], which owns the framing decision.
  Future<void> _updateIdentity(CameraImage image) async {
    final controller = ref.read(cameraNotifierProvider.notifier).controller;
    final sensor = controller?.description.sensorOrientation ?? 0;
    final lines =
        await _textRecognizer.recognize(image, sensorOrientation: sensor);
    if (!mounted) return;

    // Nothing readable this frame — leave the verdict UNKNOWN rather than
    // "unidentified". A glossy or badly-lit document that OCR can't read must
    // not become a document iOS refuses to ever capture.
    if (lines.isEmpty) {
      _identity = null;
      return;
    }

    final state = ref.read(kYCNotifierProvider);
    final mrz = extractMrz(lines);
    final wantsMrz = _wantsMrz;
    if (mrz != null && wantsMrz && state.mrzScan == null) {
      ref.read(kYCNotifierProvider.notifier).setMrzScan(mrz);
    }
    final idType = state.selectedIdType;
    if (idType == null) return;
    _identity = verifyDocumentIdentity(
      lines,
      country: effectiveCountry(ref.read(kycConfigProvider), state),
      idType: idType.key,
      requireValidMrz: wantsMrz,
      hasValidMrz: mrz != null,
      mrzAlreadyCaptured: state.mrzScan != null,
    );
  }

  /// Android auto-capture: recognize text on the frame, read the MRZ live (for
  /// passports — it both stores the chip key and triggers capture), and let the
  /// text gate decide when a document is framed steadily enough to shoot.
  Future<void> _detectFrameText(CameraImage image) async {
    final controller = ref.read(cameraNotifierProvider.notifier).controller;
    final sensor = controller?.description.sensorOrientation ?? 0;
    final lines =
        await _textRecognizer.recognize(image, sensorOrientation: sensor);
    if (!mounted || _isCapturing) return;
    await _applyTextLines(lines);
  }

  /// Same auto-capture decision, fed by the NATIVE camera — which runs ML Kit on
  /// frames it already owns and streams the recognized lines here, so no camera
  /// frame crosses the method channel per tick.
  void _onNativeText(RecognizedFrame frame) {
    if (!mounted || _isCapturing || _isUploading || _restartingClip) return;
    if (!_inCameraPhase) return;
    unawaited(_applyTextLines(frame.lines, bounds: frame.bounds));
  }

  /// Turns one frame's recognized lines into framing guidance, storing a valid
  /// MRZ on the way through (the chip key), and fires auto-capture when the gate
  /// says the document has been held steady enough.
  Future<void> _applyTextLines(List<String> lines, {Rect? bounds}) async {
    final state = ref.read(kYCNotifierProvider);
    final mrz = extractMrz(lines);
    final wantsMrz = _wantsMrz;
    if (mrz != null && wantsMrz && state.mrzScan == null) {
      ref.read(kYCNotifierProvider.notifier).setMrzScan(mrz);
    }

    final idType = state.selectedIdType;
    if (idType == null) return;
    if (kDebugMode && mrz != null && state.mrzScan == null) {
      debugPrint('[MyazaKYC] MRZ read live during framing');
    }
    final guidance = _textGate.update(
      lines,
      country: effectiveCountry(ref.read(kycConfigProvider), state),
      idType: idType.key,
      textBounds: bounds,
      // The chip step reads the MRZ off this capture, so don't shoot a frame
      // whose MRZ we couldn't read — that is what forced a second scan.
      requireMrz: wantsMrz,
      // This frame's MRZ vs the session's: a stored MRZ satisfies the chip
      // step, but only a legible one right now justifies shooting instantly.
      hasValidMrz: mrz != null,
      mrzAlreadyCaptured: state.mrzScan != null,
    );
    if (guidance.framing != _framing || guidance.hint != _hint) {
      setState(() {
        _framing = guidance.framing;
        _hint = guidance.hint;
      });
    }
    // Armed check LAST, so the gates still guide the user during the settle
    // window — they simply may not shoot yet.
    if (guidance.framing == DocumentFraming.ready &&
        !_isCapturing &&
        _autoCaptureArmed) {
      await _onCapture();
    }
  }

  /// True when the selected ID carries an MRZ we want to read (a chip-capable
  /// document with NFC enabled) — the passport case.
  bool get _wantsMrz {
    final idType = ref.read(kYCNotifierProvider).selectedIdType;
    return idType != null &&
        idType.supportsNfc &&
        ref.read(kycConfigProvider).nfc?.enabled == true;
  }

  Future<void> _detectFrame(CameraImage image) async {
    final detection = await _detector.detect(image);
    if (!mounted) return;
    var guidance = _gate.update(
      detection?.box,
      brightness: detection?.brightness ?? 0.5,
    );

    // Framed like a document, but text recognition says it is not the document
    // the user picked — hold, and say why. A null verdict means identity could
    // not be established at all this frame, which must not block the shot.
    final identity = _identity;
    if (guidance.framing == DocumentFraming.ready &&
        identity != null &&
        !identity.identified) {
      guidance = DocumentGuidance(
        identity.hint == DocumentHint.wrongDocument
            ? DocumentFraming.wrongShape
            : DocumentFraming.adjust,
        identity.hint,
      );
    }

    if (guidance.framing != _framing || guidance.hint != _hint) {
      setState(() {
        _framing = guidance.framing;
        _hint = guidance.hint;
      });
    }
    // Armed check LAST, so the gates still guide the user during the settle
    // window — they simply may not shoot yet.
    if (guidance.framing == DocumentFraming.ready &&
        !_isCapturing &&
        _autoCaptureArmed) {
      await _onCapture();
    }
  }

  /// Stops the active recording and stores the file path for the side
  /// currently being captured. Returns silently if no recording is active.
  /// The video is compressed later, at upload time, under the loading state.
  Future<void> _stopAndStoreVideoForCurrentSide() async {
    final String? path;
    final native = _nativeCamera;
    if (native != null) {
      path = await native.stopRecording();
    } else {
      final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
      if (!cameraNotifier.isRecordingVideo) return;
      path = await cameraNotifier.stopVideoRecording();
    }
    if (kDebugMode) {
      debugPrint('[MyazaKYC] side clip stored: phase=$_phase path=$path');
    }
    if (path == null) return;
    if (_phase == _ScanPhase.cameraFront) {
      _frontVideoPath = path;
    } else if (_phase == _ScanPhase.cameraBack) {
      _backVideoPath = path;
    }
  }

  // ── Phase helpers ──────────────────────────────────────────────────────────

  bool get _needsBack {
    final cfg = ref.read(kYCNotifierProvider).selectedIdType;
    return cfg?.scanSides == ScanSides.frontAndBack;
  }

  /// Clears the auto-capture latch so the next side (or a retake) starts a
  /// fresh dwell instead of inheriting the previous shot's "already fired".
  /// How long after the camera appears before auto-capture may fire.
  ///
  /// Without it the shutter can go the instant a document drifts through the
  /// frame — before the user has the phone where they want it — and the photo
  /// they get is the one they were still lining up. The gates' own stability
  /// dwell (~700ms) is about holding STILL, which is a different thing from
  /// giving someone time to get into position.
  static const _settleDelay = Duration(milliseconds: 2500);

  DateTime? _armedAt;

  /// False while the camera is still settling — the gates keep measuring and
  /// guiding, they just may not pull the trigger yet.
  bool get _autoCaptureArmed {
    final armed = _armedAt;
    return armed != null &&
        DateTime.now().difference(armed) >= _settleDelay;
  }

  void _resetAutoCapture() {
    _armedAt = DateTime.now();
    _gate.reset();
    _textGate.reset();
    if (_framing != DocumentFraming.none || _hint != DocumentHint.searching) {
      setState(() {
        _framing = DocumentFraming.none;
        _hint = DocumentHint.searching;
      });
    }
  }

  void _setPhase(_ScanPhase phase) {
    setState(() => _phase = phase);
    // Keep the parent step header title in sync.
    final phaseStr = switch (phase) {
      _ScanPhase.cameraFront => 'camera',
      _ScanPhase.frontPreview => 'front_preview',
      _ScanPhase.cameraBack   => 'camera_back',
      _ScanPhase.review       => 'review',
    };
    ref.read(kYCNotifierProvider.notifier).setDocReviewPhase(phaseStr);
  }

  // ── Capture (still photo, then crop to card region) ───────────────────────

  Future<void> _onCapture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final Uint8List? bytes;
      final native = _nativeCamera;
      if (native != null) {
        // Shoot first: the native still is an independent ImageCapture use case,
        // so nothing has to be torn down for it and the clip ends up covering
        // the moment of capture.
        bytes = await native.captureStill(
          quality: CaptureConfig.documentImageQuality,
        );
        if (!mounted) return;
        await _stopAndStoreVideoForCurrentSide();
      } else {
        // Plugin path: stop recording first — `takePicture` cannot run
        // concurrently with video recording on Android.
        await _stopAndStoreVideoForCurrentSide();
        if (!mounted) return;
        bytes = await ref.read(cameraNotifierProvider.notifier).captureImage();
      }
      if (!mounted || bytes == null) {
        if (mounted) _abortCapture();
        return;
      }

      // Crop the full camera frame down to the card-guide rectangle.
      // viewW = screen width minus the bottom sheet's 16 px left+right padding;
      // viewH is the shared constant the viewfinder is built from.
      // A large maxBytes keeps the crop at full quality here — the OCR-grade
      // sizing happens in compressDocumentImage below (quality 90, ≥1080 px).
      final idType = ref.read(kYCNotifierProvider).selectedIdType!;
      // Measured during build; the fallback only covers a capture fired before
      // the first layout, which the shutter and the gate both make impossible.
      // It mirrors the full-screen layout, so even that path crops the region
      // the user actually framed.
      final view = _viewfinderSize ?? MediaQuery.of(context).size;
      final croppedRaw = await cropCardRegionBytes(
        bytes,
        viewW: view.width,
        viewH: view.height,
        // Mirror the guide aspect so the crop matches what the user framed —
        // taller for passports so the bottom MRZ band isn't cut off.
        aspect: documentGuideAspect(idType),
        maxBytes: 1 << 24, // 16 MB — effectively "don't degrade while cropping"
      );
      if (!mounted) return;
      final cropped = await compressDocumentImage(croppedRaw);
      if (!mounted) return;

      if (_phase == _ScanPhase.cameraFront) {
        setState(() {
          _frontBytes = cropped;
          _isCapturing = false;
        });
        _maybeReadMrz([bytes, cropped]);
        _resetAutoCapture();
        _setPhase(_needsBack ? _ScanPhase.frontPreview : _ScanPhase.review);
      } else {
        setState(() {
          _backBytes = cropped;
          _isCapturing = false;
        });
        _resetAutoCapture();
        _setPhase(_ScanPhase.review);
      }
    } catch (_) {
      if (mounted) _abortCapture();
    }
  }

  /// Recovers from a shot that produced nothing.
  ///
  /// The gate LATCHED when it fired, so it must be reset or the next frame
  /// re-triggers capture — on the plugin path that was hidden (a failed capture
  /// also killed the frame stream), but the native camera's analysis stream
  /// keeps running, which would turn a single failure into a capture loop.
  void _abortCapture() {
    _resetAutoCapture();
    setState(() => _isCapturing = false);
    // The side clip was closed before the shot — start a fresh one so a retry
    // still records the side. (The plugin path restores its own recording
    // through _restartCamera.) Only while a camera phase is actually on screen:
    // a capture that failed because the screen was leaving would otherwise open
    // a clip nothing will ever record into.
    final native = _nativeCamera;
    if (native != null && _inCameraPhase) unawaited(native.startRecording());
  }

  // ── MRZ (chip key) read off the captured photo ──────────────────────────────
  //
  // The eMRTD chip's BAC key IS the printed MRZ, and the photo page the user
  // just captured already contains it — so we read it here rather than making
  // the chip step run a second camera pass. Merging the two is the whole point:
  // scanning the same document twice is a step users shouldn't have to take.
  //
  // Best-effort by contract: the chip step falls back to its own scanner when
  // this finds nothing (a gallery photo cropped past the MRZ band, a blurry
  // capture), and a failure here never blocks document capture.

  /// Reads the chip key off the photo just taken, when the live pass didn't
  /// already have it.
  ///
  /// [candidates] are tried in order — the FULL still first, then the cropped
  /// one. The crop is taken to the guide rectangle, so a document framed a
  /// little low loses its MRZ band to the crop while the full frame still has
  /// it; trying only the crop threw away the better image. Whichever hits
  /// first wins, and failing both simply leaves the chip step to scan for
  /// itself, exactly as before.
  void _maybeReadMrz(List<Uint8List> candidates) {
    final state = ref.read(kYCNotifierProvider);
    final idType = state.selectedIdType;
    if (idType == null || !idType.supportsNfc) return;
    if (ref.read(kycConfigProvider).nfc?.enabled != true) return;
    if (state.mrzScan != null) return; // already have one

    unawaited(() async {
      final recognizer = TextRecognitionService();

      // The MRZ band, enlarged, tried FIRST. A general text recogniser handed a
      // whole data page competes with the printed fields, the portrait and the
      // security pattern; handed just the strip it needs, at a workable pixel
      // height, OCR-B reads far more reliably. Failing to produce the crop is
      // not a failure — the full frames below still get their turn.
      final ordered = <Uint8List>[];
      for (final bytes in candidates) {
        try {
          final band = await cropMrzBand(bytes);
          if (band != null) ordered.add(band);
        } catch (_) {
          // Never fatal — the full frames below still get their turn.
        }
      }
      ordered.addAll(candidates);

      for (final bytes in ordered) {
        try {
          final lines = await recognizer.recognizeBytes(bytes);
          if (!mounted) return;
          if (lines.isEmpty) continue;
          final scan = extractMrz(lines);
          if (scan == null) {
            if (kDebugMode) {
              debugPrint('[MyazaKYC] MRZ: ${lines.length} lines, no valid zone');
            }
            continue;
          }
          if (kDebugMode) {
            debugPrint('[MyazaKYC] MRZ read from captured photo');
          }
          ref.read(kYCNotifierProvider.notifier).setMrzScan(scan);
          return;
        } catch (_) {
          // Never surfaces — the chip step's own scanner is the fallback.
        }
      }
      if (kDebugMode) {
        debugPrint('[MyazaKYC] MRZ: not found in the capture — chip step will '
            'need its own scan');
      }
    }());
  }

  // ── Upload from gallery (opens interactive cropper before storing) ───────────

  Future<void> _onUpload() async {
    if (_isCapturing || _isUploading) return;

    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;

    final rawBytes = await picked.readAsBytes();
    if (!mounted) return;

    // Show the interactive ID-card cropper and wait for the user to confirm.
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DocumentCropperScreen(imageBytes: rawBytes),
      ),
    );
    if (!mounted || cropped == null) return; // user cancelled

    setState(() => _isCapturing = true);
    try {
      // Stop and discard the in-progress recording — a gallery photo is not
      // a representation of what the camera was filming.
      final native = _nativeCamera;
      if (native != null) {
        await native.stopRecording();
      } else {
        final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
        if (cameraNotifier.isRecordingVideo) {
          await cameraNotifier.stopVideoRecording();
        }
      }
      if (!mounted) return;

      // A gallery photo is still an OCR document — compress conservatively.
      final compressed = await compressDocumentImage(cropped);
      if (!mounted) return;

      if (_phase == _ScanPhase.cameraFront) {
        setState(() {
          _frontBytes = compressed;
          _frontVideoPath = null;
          _isCapturing = false;
        });
        _maybeReadMrz([compressed]);
        _resetAutoCapture();
        _setPhase(_needsBack ? _ScanPhase.frontPreview : _ScanPhase.review);
      } else {
        setState(() {
          _backBytes = compressed;
          _backVideoPath = null;
          _isCapturing = false;
        });
        _resetAutoCapture();
        _setPhase(_ScanPhase.review);
      }
    } catch (_) {
      if (mounted) {
        _resetAutoCapture();
        setState(() => _isCapturing = false);
      }
    }
  }

  // ── Navigation between phases ──────────────────────────────────────────────

  void _proceedToBack() {
    _setPhase(_ScanPhase.cameraBack);
    unawaited(_resumeCaptureForSide());
  }

  /// Reports a denied camera permission to onError exactly once (deferred so it
  /// runs after the current build).
  void _reportCameraPermissionDenied(String? message) {
    if (_cameraPermissionReported) return;
    _cameraPermissionReported = true;
    final error = KYCError(
      code: 'camera_permission_denied',
      message: message ??
          'Camera access is required to photograph your document. Please allow camera access, or upload a photo instead.',
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onError?.call(error));
  }

  void _retakeFront() {
    setState(() {
      _frontBytes = null;
      _backBytes = null;
      _frontVideoPath = null;
      _backVideoPath = null;
      _uploadError = null;
    });
    _setPhase(_ScanPhase.cameraFront);
    unawaited(_resumeCaptureForSide());
  }

  void _retakeBack() {
    setState(() {
      _backBytes = null;
      _backVideoPath = null;
      _uploadError = null;
    });
    _setPhase(_ScanPhase.cameraBack);
    unawaited(_resumeCaptureForSide());
  }

  // ── Continue — upload to /api/kyc/upload, then advance ────────────────────

  Future<void> _onContinue() async {
    if (_isUploading || _frontBytes == null) return;

    setState(() {
      _isUploading = true;
      _uploadError = null;
      _uploadRetryInfo = null;
    });

    void onRetry(int attempt, int total) {
      if (mounted) setState(() => _uploadRetryInfo = (attempt: attempt, total: total));
    }

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final api = notifier.api;

      // Upload front (retried on transient failures: network / timeout / 5xx)
      final frontMediaId = await withRetry(
        () => api.upload(_frontBytes!, 'image/jpeg', MediaType.documentFront),
        onRetry: onRetry,
      );
      if (!mounted) return;
      notifier.setDocumentMediaId(frontMediaId, side: 'front');

      // Upload front video (best-effort — skip if not recorded or if its upload
      // fails after retries). Compress aggressively first.
      if (_frontVideoPath != null) {
        try {
          final frontVideoBytes = await compressVideoToBytes(
            _frontVideoPath!,
            label: 'document front video',
          );
          if (!mounted) return;
          // The side clip is best-effort — an empty one is simply no clip, and
          // uploading zero bytes would be worse than omitting it.
          if (frontVideoBytes.isEmpty) throw const _EmptyClip();
          final frontVideoMediaId = await withRetry(
            () => api.upload(frontVideoBytes, 'video/mp4', MediaType.documentFrontVideo),
          );
          if (!mounted) return;
          notifier.setMediaId('documentFrontVideo', frontVideoMediaId);
        } catch (_) {/* best-effort */}
      }

      // Upload back if captured
      if (_backBytes != null) {
        final backMediaId = await withRetry(
          () => api.upload(_backBytes!, 'image/jpeg', MediaType.documentBack),
          onRetry: onRetry,
        );
        if (!mounted) return;
        notifier.setDocumentMediaId(backMediaId, side: 'back');
      }

      // Upload back video (best-effort)
      if (_backVideoPath != null) {
        try {
          final backVideoBytes = await compressVideoToBytes(
            _backVideoPath!,
            label: 'document back video',
          );
          if (!mounted) return;
          // The side clip is best-effort — an empty one is simply no clip, and
          // uploading zero bytes would be worse than omitting it.
          if (backVideoBytes.isEmpty) throw const _EmptyClip();
          final backVideoMediaId = await withRetry(
            () => api.upload(backVideoBytes, 'video/mp4', MediaType.documentBackVideo),
          );
          if (!mounted) return;
          notifier.setMediaId('documentBackVideo', backVideoMediaId);
        } catch (_) {/* best-effort */}
      }

      if (!mounted) return;
      notifier.nextStep();
    } on KYCApiException catch (e) {
      if (!mounted) return;
      // Retries exhausted — show the inline error AND report a typed error.
      final kycError = mapToKycError(e, context: ErrorContext.upload);
      setState(() {
        _isUploading = false;
        _uploadRetryInfo = null;
        _uploadError = kycError.message;
      });
      widget.onError?.call(kycError);
    } catch (e) {
      if (!mounted) return;
      final kycError = mapToKycError(e, context: ErrorContext.upload);
      setState(() {
        _isUploading = false;
        _uploadRetryInfo = null;
        _uploadError = kycError.message;
      });
      widget.onError?.call(kycError);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final kycState     = ref.watch(kYCNotifierProvider);
    final cameraState  = ref.watch(cameraNotifierProvider);
    final controller   = ref.read(cameraNotifierProvider.notifier).controller;
    final idTypeConfig = kycState.selectedIdType!;

    // Camera permission denied during a capture phase — show a dedicated screen.
    // Document capture still offers a gallery-upload fallback, so we surface that
    // as a secondary action. onError is reported once.
    final inCameraPhase = _inCameraPhase;

    // The full-bleed camera is on screen only for the capture phases, and only
    // once the primer and permission screens are out of the way — those, the
    // preview and the review all keep the sheet's chrome.
    _syncImmersive(inCameraPhase &&
        _ready &&
        !_showPrimer &&
        !(cameraState.isPermissionDenied || _permissionDenied));

    // "Here's what happens next" — shown before the permission primer, so the
    // viewfinder never appears unannounced. Ordering matters: what we're about
    // to do, THEN the OS prompt.
    if (!_ready && inCameraPhase) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The web shows which document is expected on this screen too — it
          // is the last point before the camera where the user can still go
          // back and pick a different ID.
          _RequiredPill(idTypeLabel: idTypeConfig.label),
          const SizedBox(height: MyazaSpacing.md),
          // Expanded, because the step now fills the viewport rather than
          // sitting inside the sheet's scroll view: the primer scrolls itself,
          // and an unbounded child in a bounded Column overflows instead of
          // scrolling — which is exactly how it broke on a short screen.
          Expanded(
            child: ReadyPrimer(
              content: readyDocument,
              onReady: () {
                setState(() => _ready = true);
                _maybePrime(); // now: OS prompt, or straight to the camera
              },
            ),
          ),
        ],
      );
    }

    // Camera-access primer — shown before the OS prompt (camera not yet started).
    if (_showPrimer && inCameraPhase) {
      return CameraPermissionPrimingView(
        message:
            'When prompted, allow camera access to photograph your document.',
        onGrant: () {
          setState(() => _showPrimer = false);
          _init();
        },
      );
    }

    if ((cameraState.isPermissionDenied || _permissionDenied) && inCameraPhase) {
      _reportCameraPermissionDenied(cameraState.error);
      // The gallery fallback is always offered here as an escape hatch — even
      // when `allowDocumentUpload` is false — so a permission denial never
      // hard-stops the user with no way to provide their document.
      return CameraPermissionView(
        message: cameraState.error ??
            'Camera access is required to photograph your document. Please allow camera access, or upload a photo instead.',
        onOpenSettings: openDeviceAppSettings,
        // iOS: re-checking in place can't succeed (only Settings can grant, and
        // that relaunches the app), so omit "Try Again" there.
        onRetry: Platform.isIOS
            ? null
            : () {
                _cameraPermissionReported = false;
                _restartCamera();
              },
        secondaryAction: MyazaButton.ghost(
          label: 'Upload a photo instead',
          onPressed: _onUpload,
        ),
      );
    }

    return switch (_phase) {
      _ScanPhase.cameraFront || _ScanPhase.cameraBack => _buildCamera(
          controller: cameraState.isReady ? controller : null,
          // Native and plugin never run together — a live texture means the
          // native camera owns the feed and the plugin state is irrelevant.
          isLoading: _nativeTextureId == null &&
              (cameraState.isLoading || _initializing),
          error: _nativeTextureId == null ? cameraState.error : null,
          phase: _phase,
          idTypeConfig: idTypeConfig,
          isTwoSided: _needsBack,
        ),
      _ScanPhase.frontPreview => _buildFrontPreview(idTypeConfig),
      _ScanPhase.review       => _buildReview(idTypeConfig),
    };
  }

  // ── Camera view ────────────────────────────────────────────────────────────

  Widget _buildCamera({
    required CameraController? controller,
    required bool isLoading,
    required String? error,
    required _ScanPhase phase,
    required IdTypeConfig idTypeConfig,
    required bool isTwoSided,
  }) {
    final isBack = phase == _ScanPhase.cameraBack;
    final nativeTextureId = _nativeTextureId;
    final isReady = nativeTextureId != null || controller != null;

    Widget viewfinder() => DocumentViewfinder(
          controller: controller,
          nativeTextureId: nativeTextureId,
          nativePreviewW: _nativePreviewW,
          nativePreviewH: _nativePreviewH,
          isLoading: isLoading,
          error: error,
          isBack: isBack,
          isProcessing: _isCapturing,
          guideAspect: documentGuideAspect(idTypeConfig),
          torchOn: _torchOn,
          onToggleTorch:
              _hasTorch && isReady ? () => unawaited(_toggleTorch()) : null,
          framing: _framing,
          scanProgress: Platform.isAndroid
              ? _textGate.progress(DateTime.now())
              : _gate.progress(DateTime.now()),
          hint: _hint,
          hintLabel: idTypeConfig.label,
          // Which document, and from where — the header that used to say so is
          // gone in full-screen.
          idType: idTypeConfig,
          country: effectiveCountry(ref.read(kycConfigProvider),
              ref.read(kYCNotifierProvider)),
          showMrzBand: idTypeConfig.key == 'passport',
          onCapture: isReady && !_isCapturing ? _onCapture : null,
          onBack: _onImmersiveBack,
          onUpload: ref.read(kycConfigProvider).allowDocumentUpload
              ? _onUpload
              : null,
        );

    // ── Full-screen camera ────────────────────────────────────────────────
    // The boxed viewfinder left the shutter below the fold on a short phone,
    // so the camera owns the display here: the sheet's header and padding are
    // dropped (see setImmersiveCapture) and every control moves in-frame.
    //
    // LayoutBuilder is not decoration — the crop maps the guide back into the
    // still against the viewfinder's box, so it records the size actually laid
    // out rather than one recomputed from a constant that could drift.
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewfinderSize = constraints.biggest;
        return viewfinder();
      },
    );
  }

  /// Back from the full-screen camera. The sheet's own back control is hidden,
  /// so this stands in for it: leave the camera, and let the shell restore its
  /// chrome before the previous step draws.
  void _onImmersiveBack() {
    _syncImmersive(false);
    ref.read(kYCNotifierProvider.notifier).previousStep();
  }

  // ── Front preview ──────────────────────────────────────────────────────────

  Widget _buildFrontPreview(IdTypeConfig idTypeConfig) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Required pill + step label
        _RequiredPill(
          idTypeLabel: idTypeConfig.label,
          sideBadge: 'Front Side',
          stepLabel: 'Step 1 of 2',
        ),
        const SizedBox(height: MyazaSpacing.md),

        // Captured front image. Expanded + contain rather than natural height
        // + cover: the step fills the viewport now, so an image sized to its
        // own aspect pushes the buttons off a short screen with nothing to
        // scroll. Letting it take the room that's left keeps the whole
        // document visible AND the actions on screen.
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MyazaRadius.md),
            child: Image.memory(_frontBytes!, fit: BoxFit.contain),
          ),
        )
            .animate()
            .fadeIn(duration: 300.ms)
            .scale(
              begin: const Offset(0.96, 0.96),
              end: const Offset(1.0, 1.0),
              duration: 300.ms,
              curve: Curves.easeOut,
            ),

        const SizedBox(height: MyazaSpacing.lg),

        // Retake / Next buttons — stack vertically on narrow screens (< 400 dp)
        // so "Next — Scan Back" never overflows on phones like the S24.
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 400;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MyazaButton(
                    label: 'Next — Scan Back',
                    onPressed: _proceedToBack,
                    leadingIcon: const Icon(LucideIcons.arrowRight),
                  ),
                  const SizedBox(height: MyazaSpacing.sm),
                  MyazaButton.outline(
                    label: 'Retake',
                    onPressed: _retakeFront,
                    leadingIcon: const Icon(LucideIcons.rotateCcw),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: MyazaButton.outline(
                    label: 'Retake',
                    onPressed: _retakeFront,
                    leadingIcon: const Icon(LucideIcons.rotateCcw),
                  ),
                ),
                const SizedBox(width: MyazaSpacing.md),
                Expanded(
                  child: MyazaButton(
                    label: 'Next — Scan Back',
                    onPressed: _proceedToBack,
                    leadingIcon: const Icon(LucideIcons.arrowRight),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ── Review ─────────────────────────────────────────────────────────────────

  Widget _buildReview(IdTypeConfig idTypeConfig) {
    final busyOverlay = _isUploading
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
            ),
            child: Center(
              child: _PulseLoader(color: context.myazaColors.primary),
            ),
          ).animate().fadeIn(duration: 200.ms)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RequiredPill(idTypeLabel: idTypeConfig.label),
        const SizedBox(height: MyazaSpacing.md),
        Expanded(
          child: DocumentReview(
            front: _frontBytes!,
            back: _backBytes,
            aspect: documentGuideAspect(idTypeConfig),
            isBusy: _isUploading,
            busyOverlay: busyOverlay,
            onRetakeFront: _retakeFront,
            onRetakeBack: _retakeBack,
            footer: _buildReviewFooter(),
          ),
        ),
      ],
    );
  }

  /// Errors, the retry notice and the primary action — pinned by
  /// [DocumentReview] so they can never fall below the fold.
  Widget _buildReviewFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_uploadRetryInfo != null && _isUploading) ...[
          Text(
            'Upload failed — retrying (${_uploadRetryInfo!.attempt}/${_uploadRetryInfo!.total})…',
            style: context.myazaText.bodySmall
                .copyWith(color: const Color(0xFF92400E)), // amber-800
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MyazaSpacing.sm),
        ],
        if (_uploadError != null) ...[
          MyazaAlert(
            variant: MyazaAlertVariant.error,
            title: 'Upload failed',
            message: _uploadError!,
            onDismiss: () => setState(() => _uploadError = null),
          )
              .animate()
              .fadeIn(duration: 250.ms)
              .slideY(begin: -0.2, end: 0, duration: 250.ms),
          const SizedBox(height: MyazaSpacing.sm),
        ],
        if (!_isUploading)
          MyazaButton(
            label: _uploadError != null ? 'Try Again' : 'Continue',
            onPressed: _onContinue,
            leadingIcon: Icon(
              _uploadError != null ? LucideIcons.rotateCcw : LucideIcons.check,
            ),
          ),
      ],
    );
  }
}

// ─── Required pill ────────────────────────────────────────────────────────────

class _RequiredPill extends StatelessWidget {
  final String idTypeLabel;
  final String? sideBadge;
  final String? stepLabel;

  const _RequiredPill({
    required this.idTypeLabel,
    this.sideBadge,
    this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.primary50,
              borderRadius: BorderRadius.circular(MyazaRadius.full),
              border: Border.all(color: colors.primary200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.creditCard,
                    size: 13, color: colors.primary),
                const SizedBox(width: 5),
                Text(
                  'Required:  $idTypeLabel',
                  style: text.bodySmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sideBadge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary100,
                      borderRadius:
                          BorderRadius.circular(MyazaRadius.full),
                    ),
                    child: Text(
                      sideBadge!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (stepLabel != null) ...[
          const SizedBox(width: MyazaSpacing.sm),
          Text(stepLabel!, style: text.bodySmall),
        ],
      ],
    );
  }
}

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
