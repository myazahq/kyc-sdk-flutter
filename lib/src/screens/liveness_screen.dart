import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../config/capture_config.dart';
import '../config/theme.dart';
import '../liveness/face_detection.dart';
import '../liveness/liveness_types.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../providers/liveness_provider.dart';
import '../services/api_service.dart';
import '../services/media_compress_service.dart';
import '../widgets/liveness_avatar.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/myaza_button.dart';

// ─── Liveness screen ──────────────────────────────────────────────────────────

class LivenessScreen extends ConsumerStatefulWidget {
  const LivenessScreen({super.key});

  @override
  ConsumerState<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends ConsumerState<LivenessScreen> {
  final FaceDetectorService _detector = createFaceDetectorService();
  final _TtsService _tts = _TtsService();
  final _BrightnessSampler _brightnessSampler = _BrightnessSampler();

  bool _processing = false;
  bool _capturingHandled = false;
  bool _completionHandled = false;
  int _sensorOrientation = 0;
  bool _isDim = false;

  bool _isUploadingSelfie = false;
  String? _selfieUploadError;

  // Liveness video file path — recorded after the challenge sequence and
  // compressed + uploaded alongside the selfie. Kept locally (as a path so it
  // can be handed to VideoCompress) until [_onSelfieAccepted].
  String? _livenessVideoPath;

  @override
  void initState() {
    super.initState();
    _tts.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _detector.dispose();
    _tts.dispose();
    super.dispose();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (!mounted) return;

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

    // ML Kit needs the image stream for face detection. Most Android devices
    // (CameraX) max out at 3 concurrent use cases — adding VideoCapture here
    // silently drops ImageAnalysis and breaks gesture detection. So we stream
    // for gestures, then switch to recording mode for a brief clip in
    // [_handleCapture] once challenges pass.
    await ref
        .read(cameraNotifierProvider.notifier)
        .startStream(_onCameraImage);
    if (!mounted) return;

    ref.read(livenessNotifierProvider.notifier).startDetection();
  }

  // ── Camera image stream ────────────────────────────────────────────────────

  void _onCameraImage(CameraImage image) {
    if (_processing || !mounted) return;
    _processing = true;

    // Sample brightness (throttled to ~800ms). Only update state when it
    // actually changes to avoid unnecessary rebuilds.
    _checkBrightness(image);

    _detector
        .detect(image, sensorOrientation: _sensorOrientation)
        .then((faceData) {
      if (!mounted) { _processing = false; return; }
      final notifier = ref.read(livenessNotifierProvider.notifier);
      if (faceData != null) {
        notifier.processFrame(faceData);
      } else {
        notifier.reportNoFace();
      }
      _processing = false;
    }).catchError((_) { _processing = false; });
  }

  void _checkBrightness(CameraImage image) {
    final wasDim = _isDim;
    final brightness = _brightnessSampler.sample(image);
    if (brightness == null) return; // not yet time to sample
    final nowDim = brightness < (_BrightnessSampler.dimThreshold / 255.0);
    if (nowDim != wasDim && mounted) {
      setState(() => _isDim = nowDim);
    }
  }

  // ── Phase handlers ─────────────────────────────────────────────────────────

  Future<void> _handleCapture() async {
    if (_capturingHandled) return;
    _capturingHandled = true;

    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);

    // Stop the gesture-detection image stream so we can free a use-case slot
    // for VideoCapture (CameraX max 3 concurrent use cases on most devices).
    await cameraNotifier.stopStream();
    if (!mounted) return;

    // Record a brief post-challenge clip for the audit trail. The gesture
    // sequence itself is detected in real time via image analysis above and
    // can't be co-recorded on this hardware — this clip captures the user's
    // face immediately after challenges pass, proving they were present.
    await cameraNotifier.startVideoRecording();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final videoPath = await cameraNotifier.stopVideoRecording();
    if (!mounted) return;
    if (videoPath != null) {
      _livenessVideoPath = videoPath;
    }

    final bytes = await cameraNotifier.captureImage();
    if (!mounted) return;

    if (bytes == null) {
      _capturingHandled = false;
      _livenessVideoPath = null;
      await cameraNotifier.startStream(_onCameraImage);
      ref.read(livenessNotifierProvider.notifier).reset();
      return;
    }

    await ref.read(livenessNotifierProvider.notifier).captureSelfie(bytes);
  }

  void _handleComplete(String selfieBase64) {
    if (_completionHandled) return;
    _completionHandled = true;
    // Selfie stored in liveness state — wait for user to review and tap Continue.
  }

  /// Compress + upload the captured selfie to /api/kyc/upload, store the
  /// returned mediaId in state, and advance to the submitted step.
  Future<void> _onSelfieAccepted() async {
    if (_isUploadingSelfie) return;
    final selfieBase64 = ref.read(livenessNotifierProvider).selfieBase64;
    if (selfieBase64 == null) return;

    setState(() {
      _isUploadingSelfie = true;
      _selfieUploadError = null;
    });

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final api = notifier.api;

      // captureSelfie has already compressed the still (quality 80, ≥1080 px).
      // Upload as-is — a second pass would cost facial detail unnecessarily.
      final bytes = base64Decode(selfieBase64);
      if (!mounted) return;

      final selfieMediaId = await api.upload(
        bytes,
        'image/jpeg',
        MediaType.selfie,
      );
      if (!mounted) return;

      notifier.setMediaId('selfie', selfieMediaId);

      // Upload the recorded liveness video (best-effort — proceed if the
      // recording was unavailable on this device). Compress aggressively
      // first; the "Uploading…" state is already shown.
      if (_livenessVideoPath != null) {
        final videoBytes = await compressVideoToBytes(
          _livenessVideoPath!,
          label: 'liveness video',
        );
        if (!mounted) return;
        final videoMediaId = await api.upload(
          videoBytes,
          'video/mp4',
          MediaType.livenessVideo,
        );
        if (!mounted) return;
        notifier.setMediaId('livenessVideo', videoMediaId);
      }

      notifier.nextStep();
    } on KYCApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingSelfie = false;
        _selfieUploadError = e.message ?? 'Upload failed. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUploadingSelfie = false;
        _selfieUploadError = 'Upload failed. Please try again.';
      });
    }
  }

  void _retryLiveness() {
    setState(() {
      _capturingHandled = false;
      _completionHandled = false;
      _processing = false;
      _isDim = false;
      _livenessVideoPath = null;
    });
    _brightnessSampler.reset();
    ref.read(livenessNotifierProvider.notifier).reset();
    final cameraNotifier = ref.read(cameraNotifierProvider.notifier);
    final ctrl = cameraNotifier.controller;
    if (ctrl != null) {
      cameraNotifier.startStream(_onCameraImage);
    }
  }

  static String _guidanceText(String guidance) => switch (guidance) {
    'too_far'   => 'Kindly move closer',
    'too_close' => 'Kindly move further away',
    _           => '',
  };

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

      // Speak instruction when phase/challenge changes.
      if (phaseChanged && next.instruction.isNotEmpty) {
        _tts.speak(next.instruction);
      }

      // Speak position guidance when it first appears (or changes).
      if (guidanceChanged && next.positionGuidance != null) {
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

    if (livenessState.phase == LivenessPhase.loading) {
      return _LoadingView(error: cameraState.error);
    }

    return _ActiveView(
      livenessState: livenessState,
      controller: controller,
      isDim: _isDim,
      onRetry: livenessState.isFailed ? _retryLiveness : null,
      onSelfieAccepted: _onSelfieAccepted,
      onRetakeSelfie: _retryLiveness,
      isUploadingSelfie: _isUploadingSelfie,
      selfieUploadError: _selfieUploadError,
      onDismissUploadError: () => setState(() => _selfieUploadError = null),
    );
  }
}

// ─── TTS service ──────────────────────────────────────────────────────────────

class _TtsService {
  FlutterTts? _tts;

  Future<void> initialize() async {
    _tts = FlutterTts();
    await _tts!.setLanguage('en-US');
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    await _tts!.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await _tts?.stop();
    await _tts?.speak(text);
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: colors.primary,
                  strokeWidth: 2.5,
                ),
                const SizedBox(height: MyazaSpacing.md),
                Text(
                  'Loading…',
                  style: text.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Active view ──────────────────────────────────────────────────────────────
//
// Handles all phases except loading: positioning, challenge, passed,
// capturing, complete (selfie review), and failed.

class _ActiveView extends StatelessWidget {
  final LivenessState livenessState;
  final CameraController? controller;
  final bool isDim;
  final VoidCallback? onRetry;
  final VoidCallback onSelfieAccepted;
  final VoidCallback onRetakeSelfie;
  final bool isUploadingSelfie;
  final String? selfieUploadError;
  final VoidCallback onDismissUploadError;

  const _ActiveView({
    required this.livenessState,
    required this.controller,
    required this.isDim,
    required this.onSelfieAccepted,
    required this.onRetakeSelfie,
    required this.isUploadingSelfie,
    required this.selfieUploadError,
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
            timeoutRemaining: livenessState.timeoutRemaining,
            positionGuidance: livenessState.positionGuidance,
          ),
          const SizedBox(height: MyazaSpacing.sm),
          // ── Dim environment warning (non-blocking amber alert) ──────────────
          _DimWarningBanner(isDim: isDim),
          SizedBox(height: isDim ? MyazaSpacing.sm : MyazaSpacing.md),
        ] else
          const SizedBox(height: MyazaSpacing.sm),

        // ── Camera circle ─────────────────────────────────────────────────────
        Center(
          child: _CameraCircle(
            controller: controller,
            phase: phase,
            faceDetected: livenessState.faceDetected,
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
  final VoidCallback onDismissError;

  const _SelfieReviewView({
    required this.selfieBase64,
    required this.onRetake,
    required this.onContinue,
    required this.isUploading,
    required this.uploadError,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(selfieBase64);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Selfie circle ─────────────────────────────────────────────────────
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
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
                child: Image.memory(imageBytes, fit: BoxFit.cover),
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

        if (isUploading) ...[
          const SizedBox(height: MyazaSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: MyazaSpacing.md,
              horizontal: MyazaSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: context.myazaColors.primary50,
              borderRadius: BorderRadius.circular(MyazaRadius.md),
              border: Border.all(color: context.myazaColors.primary100),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: context.myazaColors.primary,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                Text(
                  'Uploading…',
                  style: context.myazaText.label
                      .copyWith(color: context.myazaColors.primary),
                ),
              ],
            ),
          ),
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
  final int timeoutRemaining;

  /// 'too_far', 'too_close', or null. When set, overrides [instruction].
  final String? positionGuidance;

  const _InstructionBanner({
    required this.phase,
    required this.instruction,
    required this.faceDetected,
    required this.timeoutRemaining,
    this.positionGuidance,
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

    final colors = context.myazaColors;
    final text   = context.myazaText;

    // Priority: no-face > position warning > challenge passed > challenge > default
    final String displayText;
    final Color  textColor;

    if (showNoFace) {
      displayText = 'No face detected';
      textColor   = MyazaColors.error;
    } else if (hasPositionWarning) {
      displayText = positionGuidance == 'too_far'
          ? 'Kindly move closer'
          : 'Kindly move further away';
      textColor = MyazaColors.error;
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

        if (isChallenge && timeoutRemaining > 0 && !hasPositionWarning) ...[
          const SizedBox(height: MyazaSpacing.sm),
          _TimeoutPill(seconds: timeoutRemaining),
        ],
      ],
    );
  }
}

class _TimeoutPill extends StatelessWidget {
  final int seconds;

  const _TimeoutPill({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    final isLow  = seconds <= 3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLow ? colors.errorBg : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        border: Border.all(
          color: isLow ? MyazaColors.error : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.timer,
              size: 13,
              color: isLow ? MyazaColors.error : colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: text.bodySmall.copyWith(
              color: isLow ? MyazaColors.error : colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Camera circle ────────────────────────────────────────────────────────────

class _CameraCircle extends StatelessWidget {
  final CameraController? controller;
  final LivenessPhase phase;
  final bool faceDetected;

  const _CameraCircle({
    required this.controller,
    required this.phase,
    required this.faceDetected,
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
    final isReady     = controller != null && controller!.value.isInitialized;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
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
              if (isReady)
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

              // Animated checkmark overlay when challenge passes
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
                      begin: const Offset(0.1, 0.1),
                      end: const Offset(1.0, 1.0),
                      duration: 400.ms,
                      curve: Curves.elasticOut,
                    )
                    .fadeIn(duration: 150.ms),
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

// ─── Dim environment warning banner ──────────────────────────────────────────
//
// Shown when the brightness sampler detects low light for 2 consecutive
// readings (~1.6 s). Non-blocking — the liveness flow continues; this is
// purely informational. Matches the web SDK's amber alert style.

class _DimWarningBanner extends StatelessWidget {
  final bool isDim;

  const _DimWarningBanner({required this.isDim});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: isDim
          ? Container(
              key: const ValueKey('dim'),
              padding: const EdgeInsets.symmetric(
                horizontal: MyazaSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),   // amber-50
                borderRadius: BorderRadius.circular(MyazaRadius.sm),
                border: Border.all(color: const Color(0xFFFDE68A)), // amber-200
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.lightbulb,
                    size: 16,
                    color: Color(0xFF92400E), // amber-800
                  ),
                  SizedBox(width: MyazaSpacing.sm),
                  Expanded(
                    child: Text(
                      'It looks dark here. Move to a brighter area or near a light source for better detection.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(key: ValueKey('bright')),
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

class _BrightnessSampler {
  static const double dimThreshold   = 62.0; // 0–255
  static const int    sampleInterval = 800;  // ms
  static const int    warmupMs       = 1500; // ms before first sample
  static const int    confirmCount   = 2;    // consecutive dark readings needed

  int? _startMs;
  int? _lastSampleMs;
  int  _darkStreak = 0;

  void reset() {
    _startMs       = null;
    _lastSampleMs  = null;
    _darkStreak    = 0;
  }

  /// Returns the mean normalised luminance [0–255] if it is time to sample,
  /// or null if the warmup / throttle interval has not elapsed.
  double? sample(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _startMs ??= now;

    if (now - _startMs! < warmupMs) return null;
    if (_lastSampleMs != null && now - _lastSampleMs! < sampleInterval) {
      return null;
    }
    _lastSampleMs = now;

    final luma = Platform.isAndroid
        ? _sampleNv21(image)
        : _sampleBgra(image);

    if (luma < dimThreshold) {
      _darkStreak++;
    } else {
      _darkStreak = 0;
    }

    // Only report "dim" after confirmCount consecutive dark readings so a
    // single dark frame (e.g. user briefly covering camera) is ignored.
    return _darkStreak >= confirmCount ? luma : dimThreshold + 1;
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
