import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../config/capture_config.dart';
import '../config/id_types.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../services/image_service.dart';
import '../services/kyc_error_mapper.dart';
import '../services/media_compress_service.dart';
import '../services/retry.dart';
import '../utils/permissions.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/camera_permission_priming_view.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/myaza_button.dart';

// ─── Scan phase ───────────────────────────────────────────────────────────────
//
// cameraFront   → camera open, scanning front side
// frontPreview  → front captured; user reviews before scanning back
// cameraBack    → camera open, scanning back side (two-sided IDs only)
// review        → both (or all) sides captured; upload runs from Continue

enum _ScanPhase { cameraFront, frontPreview, cameraBack, review }

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

  bool _isCapturing = false; // still-photo in progress
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

  /// Show the "Allow camera access" primer before requesting permission, unless
  /// the camera is already granted (in which case we open it straight away).
  Future<void> _maybePrime() async {
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
    // iOS only — see LivenessScreen. On Android the CameraX-backed camera plugin
    // is lifecycle-aware; a manual reinit on resume races CameraX's video
    // recorder teardown (fatal "onConfigured in STOPPING state" assertion).
    if (!Platform.isIOS) return;
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
      }

      await ref.read(cameraNotifierProvider.notifier).initialize(
        direction: CameraLensDirection.back,
        // Kept high (not medium) so the OCR still stays sharp — the document
        // video is shrunk by VideoCompress at encode time instead.
        resolution: CaptureConfig.documentResolution,
      );
      if (!mounted) return;
      await _startVideoRecording();
    } finally {
      _initializing = false;
    }
  }

  /// Best-effort start: records a side-specific MP4 capturing how the user
  /// presented the document. If recording fails (e.g. unsupported device),
  /// the still capture flow still works.
  Future<void> _startVideoRecording() async {
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    if (cameraNotifier.isRecordingVideo) return;
    await cameraNotifier.startVideoRecording();
  }

  /// Stops the active recording and stores the file path for the side
  /// currently being captured. Returns silently if no recording is active.
  /// The video is compressed later, at upload time, under the loading state.
  Future<void> _stopAndStoreVideoForCurrentSide() async {
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    if (!cameraNotifier.isRecordingVideo) return;
    final path = await cameraNotifier.stopVideoRecording();
    if (path == null) return;
    if (_phase == _ScanPhase.cameraFront) {
      _frontVideoPath = path;
    } else if (_phase == _ScanPhase.cameraBack) {
      _backVideoPath = path;
    }
  }

  // ── Phase helpers ──────────────────────────────────────────────────────────

  bool get _needsBack {
    final config = ref.read(kycConfigProvider);
    final idType = ref.read(kYCNotifierProvider).selectedIdType;
    final cfg = getIdTypeConfig(config.country, idType!);
    return cfg?.scanSides == ScanSides.frontAndBack;
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
      // Stop recording first — `takePicture` cannot run concurrently with
      // video recording on Android. Save the recorded bytes so they can be
      // uploaded alongside the still image on Continue.
      await _stopAndStoreVideoForCurrentSide();
      if (!mounted) return;

      final bytes =
          await ref.read(cameraNotifierProvider.notifier).captureImage();
      if (!mounted || bytes == null) {
        setState(() => _isCapturing = false);
        return;
      }

      // Crop the full camera frame down to the card-guide rectangle.
      // viewW = screen width minus the bottom sheet's 16 px left+right padding.
      // A large maxBytes keeps the crop at full quality here — the OCR-grade
      // sizing happens in compressDocumentImage below (quality 90, ≥1080 px).
      final idType = ref.read(kYCNotifierProvider).selectedIdType!;
      final viewW = MediaQuery.of(context).size.width - 2 * MyazaSpacing.md;
      final croppedRaw = await cropCardRegionBytes(
        bytes,
        viewW: viewW,
        viewH: 300.0,
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
        _setPhase(_needsBack ? _ScanPhase.frontPreview : _ScanPhase.review);
      } else {
        setState(() {
          _backBytes = cropped;
          _isCapturing = false;
        });
        _setPhase(_ScanPhase.review);
      }
    } catch (_) {
      if (mounted) setState(() => _isCapturing = false);
    }
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
        builder: (_) => _DocumentCropperScreen(imageBytes: rawBytes),
      ),
    );
    if (!mounted || cropped == null) return; // user cancelled

    setState(() => _isCapturing = true);
    try {
      // Stop and discard the in-progress recording — a gallery photo is not
      // a representation of what the camera was filming.
      final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
      if (cameraNotifier.isRecordingVideo) {
        await cameraNotifier.stopVideoRecording();
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
        _setPhase(_needsBack ? _ScanPhase.frontPreview : _ScanPhase.review);
      } else {
        setState(() {
          _backBytes = compressed;
          _backVideoPath = null;
          _isCapturing = false;
        });
        _setPhase(_ScanPhase.review);
      }
    } catch (_) {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ── Navigation between phases ──────────────────────────────────────────────

  void _proceedToBack() {
    _setPhase(_ScanPhase.cameraBack);
    _restartCamera();
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
    _restartCamera();
  }

  void _retakeBack() {
    setState(() {
      _backBytes = null;
      _backVideoPath = null;
      _uploadError = null;
    });
    _setPhase(_ScanPhase.cameraBack);
    _restartCamera();
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
    final config       = ref.read(kycConfigProvider);
    final idTypeConfig = getIdTypeConfig(config.country, kycState.selectedIdType!)!;

    // Camera permission denied during a capture phase — show a dedicated screen.
    // Document capture still offers a gallery-upload fallback, so we surface that
    // as a secondary action. onError is reported once.
    final inCameraPhase =
        _phase == _ScanPhase.cameraFront || _phase == _ScanPhase.cameraBack;

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
          isLoading: cameraState.isLoading,
          error: cameraState.error,
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
    final sideHint = isTwoSided
        ? (isBack ? ' — back side' : ' — front side')
        : '';
    final isReady = controller != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Subtitle + required pill ─────────────────────────────────────────
        Text(
          'Photograph your ${idTypeConfig.label}$sideHint — position it within the frame and hold steady.',
          style: context.myazaText.bodyMedium,
        ),
        const SizedBox(height: MyazaSpacing.sm),
        _RequiredPill(
          idTypeLabel: idTypeConfig.label,
          sideBadge: isTwoSided ? (isBack ? 'Back Side' : 'Front Side') : null,
          stepLabel: isTwoSided ? (isBack ? 'Step 2 of 2' : 'Step 1 of 2') : null,
        ),

        // Flip hint when switching to back
        if (isBack) ...[
          const SizedBox(height: MyazaSpacing.sm),
          Row(
            children: [
              Icon(LucideIcons.creditCard, size: 14,
                  color: context.myazaColors.primary),
              const SizedBox(width: 4),
              Text(
                'Flip the card over and scan the other side',
                style: context.myazaText.bodySmall.copyWith(
                  color: context.myazaColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 200.ms)
              .slideX(begin: 0.2, end: 0, duration: 400.ms, delay: 200.ms),
        ],

        const SizedBox(height: MyazaSpacing.md),

        // ── Camera viewfinder ────────────────────────────────────────────────
        _DocumentViewfinder(
          controller: isReady ? controller : null,
          isLoading: isLoading,
          error: error,
          isBack: isBack,
          isProcessing: _isCapturing,
          guideAspect: documentGuideAspect(idTypeConfig.idType),
          onCapture: isReady && !_isCapturing ? _onCapture : null,
        ),
        const SizedBox(height: MyazaSpacing.md),

        // ── Hint + upload link ───────────────────────────────────────────────
        if (!_isCapturing) ...[
          Text(
            'Tap the button to capture manually',
            style: context.myazaText.bodySmall,
            textAlign: TextAlign.center,
          ),
          // "Upload a photo instead" — hidden when device upload is disabled.
          if (ref.read(kycConfigProvider).allowDocumentUpload) ...[
            const SizedBox(height: MyazaSpacing.sm),
            GestureDetector(
              onTap: _onUpload,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Having trouble? ', style: context.myazaText.bodySmall),
                  Icon(LucideIcons.upload,
                      size: 14, color: context.myazaColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Upload a photo instead',
                    style: context.myazaText.bodySmall.copyWith(
                      color: context.myazaColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
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

        // Captured front image
        ClipRRect(
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          child: Image.memory(_frontBytes!, fit: BoxFit.cover),
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
    final hasBack = _backBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Required pill
        _RequiredPill(idTypeLabel: idTypeConfig.label),
        const SizedBox(height: MyazaSpacing.lg),

        // ── Front ──────────────────────────────────────────────────────────
        Text(
          'Front',
          style: context.myazaText.bodySmall
              .copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(MyazaRadius.md),
          child: Stack(
            children: [
              Image.memory(_frontBytes!, fit: BoxFit.cover),
              // Uploading loader rendered INSIDE the preview frame (replaces the
              // old standalone "Uploading…" pill). Mirrors the liveness selfie /
              // submitting screen's pulse-ring + spinner loader.
              if (_isUploading)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    child: Center(
                      child: _PulseLoader(color: context.myazaColors.primary),
                    ),
                  ).animate().fadeIn(duration: 200.ms),
                ),
            ],
          ),
        ),
        const SizedBox(height: MyazaSpacing.sm),
        _RetakeButton(
          label: hasBack ? 'Retake Front' : 'Retake Photo',
          onTap: _isUploading ? null : _retakeFront,
        ),

        // ── Back (if captured) ─────────────────────────────────────────────
        if (hasBack) ...[
          const SizedBox(height: MyazaSpacing.lg),
          Text(
            'Back',
            style: context.myazaText.bodySmall
                .copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MyazaSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(MyazaRadius.md),
            child: Stack(
              children: [
                Image.memory(_backBytes!, fit: BoxFit.cover),
                if (_isUploading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      child: Center(
                        child: _PulseLoader(color: context.myazaColors.primary),
                      ),
                    ).animate().fadeIn(duration: 200.ms),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MyazaSpacing.sm),
          _RetakeButton(
            label: 'Retake Back',
            onTap: _isUploading ? null : _retakeBack,
          ),
        ],

        // ── Upload retry note ──────────────────────────────────────────────
        if (_uploadRetryInfo != null && _isUploading) ...[
          const SizedBox(height: MyazaSpacing.md),
          Text(
            'Upload failed — retrying (${_uploadRetryInfo!.attempt}/${_uploadRetryInfo!.total})…',
            style: context.myazaText.bodySmall
                .copyWith(color: const Color(0xFF92400E)), // amber-800
            textAlign: TextAlign.center,
          ),
        ],

        // ── Upload error ───────────────────────────────────────────────────
        if (_uploadError != null) ...[
          const SizedBox(height: MyazaSpacing.md),
          MyazaAlert(
            variant: MyazaAlertVariant.error,
            title: 'Upload failed',
            message: _uploadError!,
            onDismiss: () => setState(() => _uploadError = null),
          )
              .animate()
              .fadeIn(duration: 250.ms)
              .slideY(begin: -0.2, end: 0, duration: 250.ms),
        ],

        // ── Continue button ────────────────────────────────────────────────
        if (!_isUploading) ...[
          const SizedBox(height: MyazaSpacing.lg),
          MyazaButton(
            label: _uploadError != null ? 'Try Again' : 'Continue',
            onPressed: _onContinue,
            leadingIcon: Icon(
              _uploadError != null
                  ? LucideIcons.rotateCcw
                  : LucideIcons.check,
            ),
          ),
        ],
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

// ─── Retake ghost button ──────────────────────────────────────────────────────

class _RetakeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _RetakeButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    final iconColor = onTap != null ? colors.textSecondary : colors.gray300;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.rotateCcw, size: 15, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: text.bodySmall.copyWith(
              color: iconColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Document viewfinder ──────────────────────────────────────────────────────

class _DocumentViewfinder extends StatelessWidget {
  final CameraController? controller;
  final bool isLoading;
  final String? error;
  final bool isBack;
  final bool isProcessing;
  final double guideAspect;
  final VoidCallback? onCapture;

  const _DocumentViewfinder({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.isBack,
    required this.isProcessing,
    required this.guideAspect,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller!.value.isInitialized)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller!.value.previewSize!.height,
                    height: controller!.value.previewSize!.width,
                    child: CameraPreview(controller!),
                  ),
                ),
              )
            else
              _ViewfinderPlaceholder(isLoading: isLoading, error: error),

            CustomPaint(
                painter: _CardGuidePainter(isBack: isBack, aspect: guideAspect)),

            // Side badge
            Positioned(
              top: 10,
              right: 10,
              child: _SideBadge(isBack: isBack),
            ),

            // "Align your ID" hint
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius:
                        BorderRadius.circular(MyazaRadius.full),
                  ),
                  child: Text(
                    isBack
                        ? 'Align the BACK of your card'
                        : 'Align your ID within the frame',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // Shutter / processing overlay at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: isProcessing
                    ? _ProcessingPill()
                    : _ShutterButton(onCapture: onCapture),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewfinderPlaceholder extends StatelessWidget {
  final bool isLoading;
  final String? error;

  const _ViewfinderPlaceholder({required this.isLoading, this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.videoOff,
                      color: Colors.white54, size: 36),
                  const SizedBox(height: MyazaSpacing.sm),
                  Text('Camera unavailable',
                      style: context.myazaText.bodySmall
                          .copyWith(color: Colors.white70)),
                ],
              )
            : CircularProgressIndicator(
                color: context.myazaColors.primary, strokeWidth: 2),
      ),
    );
  }
}

class _SideBadge extends StatelessWidget {
  final bool isBack;

  const _SideBadge({required this.isBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBack ? MyazaColors.success : context.myazaColors.primary,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Text(
        isBack ? 'BACK' : 'FRONT',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback? onCapture;

  const _ShutterButton({required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final isEnabled = onCapture != null;
    return GestureDetector(
      onTap: onCapture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isEnabled ? colors.primary : colors.gray400,
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          LucideIcons.camera,
          size: 26,
          color: isEnabled ? Colors.white : Colors.white54,
        ),
      ),
    );
  }
}

class _ProcessingPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(MyazaRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Capturing…',
            style: context.myazaText.bodySmall.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─── Card guide painter ───────────────────────────────────────────────────────

// Passport data pages are taller than a credit card and carry the 2-line MRZ
// band at the bottom — which the server OCR relies on for the passport number
// and nationality. A 1.586 card crop centred on the visual zone cuts the MRZ
// off, so passports use a taller guide/crop (≈ the ICAO TD3 125×88 mm page
// ratio) that frames the whole data page, MRZ included.
const double kCardGuideAspect = 1.586;
const double kPassportGuideAspect = 1.42;

double documentGuideAspect(IdType idType) =>
    idType == IdType.passport ? kPassportGuideAspect : kCardGuideAspect;

class _CardGuidePainter extends CustomPainter {
  final bool isBack;
  final double aspect;

  const _CardGuidePainter({required this.isBack, this.aspect = kCardGuideAspect});

  static const double _widthFraction = 0.88;
  static const double _cornerLen     = 18.0;
  static const double _cornerRadius  = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth  = size.width * _widthFraction;
    final cardHeight = cardWidth / aspect;
    // Shift upward so the shutter button fits below
    final top    = (size.height - cardHeight) / 2 - 20;
    final left   = (size.width - cardWidth) / 2;
    final right  = left + cardWidth;
    final bottom = top + cardHeight;
    final rect   = Rect.fromLTRB(left, top, right, bottom);

    // Dark overlay around the card window
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), overlay);
    canvas.drawRect(
        Rect.fromLTRB(0, bottom, size.width, size.height), overlay);
    canvas.drawRect(Rect.fromLTRB(0, top, left, bottom), overlay);
    canvas.drawRect(
        Rect.fromLTRB(right, top, size.width, bottom), overlay);

    // Card border
    final borderColor = isBack ? MyazaColors.success : Colors.white;
    final border = Paint()
      ..color = borderColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect, const Radius.circular(_cornerRadius)),
      border,
    );

    // Corner markers
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const r = _cornerRadius;
    canvas.drawLine(Offset(left + r, top),
        Offset(left + r + _cornerLen, top), corner);
    canvas.drawLine(Offset(left, top + r),
        Offset(left, top + r + _cornerLen), corner);
    canvas.drawLine(Offset(right - r - _cornerLen, top),
        Offset(right - r, top), corner);
    canvas.drawLine(Offset(right, top + r),
        Offset(right, top + r + _cornerLen), corner);
    canvas.drawLine(Offset(left + r, bottom),
        Offset(left + r + _cornerLen, bottom), corner);
    canvas.drawLine(Offset(left, bottom - r - _cornerLen),
        Offset(left, bottom - r), corner);
    canvas.drawLine(Offset(right - r - _cornerLen, bottom),
        Offset(right - r, bottom), corner);
    canvas.drawLine(Offset(right, bottom - r - _cornerLen),
        Offset(right, bottom - r), corner);
  }

  @override
  bool shouldRepaint(_CardGuidePainter old) =>
      old.isBack != isBack || old.aspect != aspect;
}

// ─── Crop params ──────────────────────────────────────────────────────────────
//
// A plain data class sent across the isolate boundary via compute().
// All fields must be sendable (primitives + Uint8List).

class _CropParams {
  final Uint8List bytes;
  final int srcX;
  final int srcY;
  final int srcW;
  final int srcH;

  const _CropParams({
    required this.bytes,
    required this.srcX,
    required this.srcY,
    required this.srcW,
    required this.srcH,
  });
}

// Top-level so compute() can run it in a separate isolate.
Uint8List _doCropImage(_CropParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) throw Exception('Could not decode image');
  final baked = img.bakeOrientation(decoded);
  final sw = p.srcW.clamp(1, baked.width - p.srcX);
  final sh = p.srcH.clamp(1, baked.height - p.srcY);
  final cropped = img.copyCrop(baked, x: p.srcX, y: p.srcY, width: sw, height: sh);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

// ─── Crop handle ──────────────────────────────────────────────────────────────

enum _CropHandle { none, move, tl, tr, bl, br }

// ─── Document cropper screen ──────────────────────────────────────────────────

class _DocumentCropperScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const _DocumentCropperScreen({required this.imageBytes});

  @override
  State<_DocumentCropperScreen> createState() => _DocumentCropperScreenState();
}

class _DocumentCropperScreenState extends State<_DocumentCropperScreen> {
  // ISO/IEC 7810 ID-1 standard: 85.6 mm × 53.98 mm → AR ≈ 1.5858
  static const double _idAR = 85.6 / 53.98;

  Size? _naturalSize;
  Rect _imgRect = Rect.zero;
  Rect _cropRect = Rect.zero;
  bool _cropInitialized = false;
  bool _isProcessing = false;

  _CropHandle _handle = _CropHandle.none;
  Offset _panStart = Offset.zero;
  Rect _cropAtPanStart = Rect.zero;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadNaturalSize();
  }

  Future<void> _loadNaturalSize() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    if (mounted) setState(() => _naturalSize = size);
  }

  // ── Geometry helpers ─────────────────────────────────────────────────────

  /// Returns the rect of the rendered image (object-contain) within [container].
  Rect _computeImgRect(Size container) {
    if (_naturalSize == null) return Rect.zero;
    final natAR = _naturalSize!.width / _naturalSize!.height;
    final conAR = container.width / container.height;
    final double rw, rh;
    if (natAR > conAR) {
      rw = container.width;
      rh = container.width / natAR;
    } else {
      rh = container.height;
      rw = container.height * natAR;
    }
    return Rect.fromLTWH(
      (container.width - rw) / 2,
      (container.height - rh) / 2,
      rw,
      rh,
    );
  }

  /// Initial crop box: 85% of image width, centered, respecting ID AR.
  Rect _initCropRect(Rect imgRect) {
    double cropW = imgRect.width * 0.85;
    double cropH = cropW / _idAR;
    if (cropH > imgRect.height * 0.9) {
      cropH = imgRect.height * 0.9;
      cropW = cropH * _idAR;
    }
    return Rect.fromLTWH(
      imgRect.left + (imgRect.width - cropW) / 2,
      imgRect.top + (imgRect.height - cropH) / 2,
      cropW,
      cropH,
    );
  }

  /// Clamps the crop rect to stay within [bounds], maintaining _idAR.
  Rect _clampCrop(Rect crop, Rect bounds) {
    double w = crop.width.clamp(60.0, bounds.width);
    double h = w / _idAR;
    if (h > bounds.height) {
      h = bounds.height;
      w = h * _idAR;
      if (w > bounds.width) {
        w = bounds.width;
        h = w / _idAR;
      }
    }
    final maxLeft = (bounds.right - w).clamp(bounds.left, bounds.right);
    final maxTop  = (bounds.bottom - h).clamp(bounds.top, bounds.bottom);
    return Rect.fromLTWH(
      crop.left.clamp(bounds.left, maxLeft),
      crop.top.clamp(bounds.top, maxTop),
      w,
      h,
    );
  }

  // ── Gesture handling ─────────────────────────────────────────────────────

  _CropHandle _hitTest(Offset pos) {
    const double r = 28.0;
    if ((pos - _cropRect.topLeft).distance     < r) return _CropHandle.tl;
    if ((pos - _cropRect.topRight).distance    < r) return _CropHandle.tr;
    if ((pos - _cropRect.bottomLeft).distance  < r) return _CropHandle.bl;
    if ((pos - _cropRect.bottomRight).distance < r) return _CropHandle.br;
    if (_cropRect.inflate(8).contains(pos)) return _CropHandle.move;
    return _CropHandle.none;
  }

  void _onPanStart(DragStartDetails d) {
    _handle = _hitTest(d.localPosition);
    _panStart = d.localPosition;
    _cropAtPanStart = _cropRect;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_handle == _CropHandle.none || _imgRect.isEmpty) return;
    final dx = d.localPosition.dx - _panStart.dx;
    final dy = d.localPosition.dy - _panStart.dy;
    final bottomEdge = _cropAtPanStart.bottom;

    final Rect newCrop;
    switch (_handle) {
      case _CropHandle.none:
        return;
      case _CropHandle.move:
        newCrop = _cropAtPanStart.translate(dx, dy);
      case _CropHandle.br:
        final w = _cropAtPanStart.width + dx;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left, _cropAtPanStart.top, w, w / _idAR);
      case _CropHandle.bl:
        final w = _cropAtPanStart.width - dx;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left + dx, _cropAtPanStart.top, w, w / _idAR);
      case _CropHandle.tr:
        final w = _cropAtPanStart.width + dx;
        final h = w / _idAR;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left, bottomEdge - h, w, h);
      case _CropHandle.tl:
        final w = _cropAtPanStart.width - dx;
        final h = w / _idAR;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left + dx, bottomEdge - h, w, h);
    }

    setState(() => _cropRect = _clampCrop(newCrop, _imgRect));
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _handle = _CropHandle.none);
  }

  // ── Confirm: crop image in isolate, pop with result ──────────────────────

  Future<void> _onConfirm() async {
    if (_naturalSize == null || _imgRect.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);

    final scaleX = _naturalSize!.width / _imgRect.width;
    final scaleY = _naturalSize!.height / _imgRect.height;

    final sx = ((_cropRect.left - _imgRect.left) * scaleX)
        .round()
        .clamp(0, _naturalSize!.width.toInt() - 1);
    final sy = ((_cropRect.top - _imgRect.top) * scaleY)
        .round()
        .clamp(0, _naturalSize!.height.toInt() - 1);
    final sw = (_cropRect.width * scaleX).round();
    final sh = (_cropRect.height * scaleY).round();

    try {
      final result = await compute(
        _doCropImage,
        _CropParams(bytes: widget.imageBytes, srcX: sx, srcY: sy, srcW: sw, srcH: sh),
      );
      if (mounted) Navigator.of(context).pop<Uint8List>(result);
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leadingWidth: 48,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.of(context).pop<Uint8List?>(null),
          tooltip: 'Cancel',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Crop to ID Card',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              'Drag to reposition · handles to resize',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        titleSpacing: 4,
      ),
      body: Column(
        children: [
          // ── Image + crop overlay ─────────────────────────────────────────
          Expanded(
            child: _naturalSize == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : LayoutBuilder(builder: (ctx, cons) {
                    final imgR = _computeImgRect(cons.biggest);
                    if (imgR != _imgRect) {
                      _imgRect = imgR;
                      if (!_cropInitialized && !imgR.isEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _cropRect = _initCropRect(imgR);
                              _cropInitialized = true;
                            });
                          }
                        });
                      }
                    }
                    return GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          if (_cropInitialized)
                            CustomPaint(
                              painter: _CropOverlayPainter(
                                imgRect: _imgRect,
                                cropRect: _cropRect,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
          ),

          // ── Action bar ───────────────────────────────────────────────────
          Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: _isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Processing…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton.icon(
                        onPressed: _cropInitialized ? _onConfirm : null,
                        icon: const Icon(LucideIcons.check, size: 18),
                        label: const Text('Crop & Use'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyazaColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Crop overlay painter ─────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final Rect imgRect;
  final Rect cropRect;

  const _CropOverlayPainter({required this.imgRect, required this.cropRect});

  static const double _armLen = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    // ── 4 dim rects around the crop window ──────────────────────────────────
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, cropRect.top), dim);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom), dim);

    // ── White 2px border ─────────────────────────────────────────────────────
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // ── Rule-of-thirds grid (25 % opacity) ──────────────────────────────────
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width / 3, cropRect.bottom),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.bottom),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height / 3),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height * 2 / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height * 2 / 3),
      grid,
    );

    // ── L-shaped corner brackets (3.5 px, round caps) ────────────────────────
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(_armLen, 0), corner);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, _armLen), corner);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-_armLen, 0), corner);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, _armLen), corner);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(_armLen, 0), corner);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -_armLen), corner);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-_armLen, 0), corner);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -_armLen), corner);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.cropRect != cropRect || old.imgRect != imgRect;
}

// ─── Pulse loader ─────────────────────────────────────────────────────────────
//
// Pulsing ring + tinted spinner badge — mirrors the liveness selfie / submitting
// screen's loader. Rendered inside the document preview frame while uploading.

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
