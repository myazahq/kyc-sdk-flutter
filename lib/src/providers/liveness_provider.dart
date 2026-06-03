import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../liveness/challenge_manager.dart';
import '../liveness/face_detection.dart';
import '../liveness/liveness_types.dart';
import '../services/image_service.dart';
import 'kyc_provider.dart';

part 'liveness_provider.g.dart';

// ─── Liveness state ───────────────────────────────────────────────────────────

class LivenessState {
  final LivenessPhase phase;

  /// Instruction text shown to the user for the current challenge.
  final String instruction;

  /// Number of challenges completed so far.
  final int completedCount;

  /// Total challenges selected for this session.
  final int totalCount;

  /// Seconds remaining for the active challenge before timeout.
  final int timeoutRemaining;

  /// Whether a face is currently detected in the frame.
  final bool faceDetected;

  /// The challenge type currently being attempted, or null when not in a
  /// challenge phase. Consumed by LivenessAvatar to drive its animation.
  final LivenessChallenge? activeChallenge;

  /// Base64-encoded JPEG selfie captured after all challenges pass.
  /// Only non-null when [phase] == [LivenessPhase.complete].
  final String? selfieBase64;

  final String? error;

  /// Distance guidance — mirrors the web SDK's position check.
  ///   'too_far'   → face width < 0.2 → "Kindly move closer"
  ///   'too_close' → face width > 0.7 → "Kindly move further away"
  ///   null        → correct distance
  /// Checked per-frame during positioning and challenge phases.
  /// Blocks challenge advancement when not null during positioning.
  final String? positionGuidance;

  const LivenessState({
    this.phase = LivenessPhase.loading,
    this.instruction = '',
    this.completedCount = 0,
    this.totalCount = 0,
    this.timeoutRemaining = 0,
    this.faceDetected = false,
    this.activeChallenge,
    this.selfieBase64,
    this.error,
    this.positionGuidance,
  });

  double get progress =>
      totalCount > 0 ? completedCount / totalCount : 0.0;

  bool get isComplete => phase == LivenessPhase.complete;
  bool get isFailed => phase == LivenessPhase.failed;

  LivenessState copyWith({
    LivenessPhase? phase,
    String? instruction,
    int? completedCount,
    int? totalCount,
    int? timeoutRemaining,
    bool? faceDetected,
    LivenessChallenge? activeChallenge,
    bool clearActiveChallenge = false,
    String? selfieBase64,
    String? error,
    String? positionGuidance,
    bool clearPositionGuidance = false,
  }) =>
      LivenessState(
        phase: phase ?? this.phase,
        instruction: instruction ?? this.instruction,
        completedCount: completedCount ?? this.completedCount,
        totalCount: totalCount ?? this.totalCount,
        timeoutRemaining: timeoutRemaining ?? this.timeoutRemaining,
        faceDetected: faceDetected ?? this.faceDetected,
        activeChallenge: clearActiveChallenge
            ? null
            : (activeChallenge ?? this.activeChallenge),
        selfieBase64: selfieBase64 ?? this.selfieBase64,
        error: error, // explicit null clears error
        positionGuidance:
            clearPositionGuidance ? null : (positionGuidance ?? this.positionGuidance),
      );
}

// ─── Liveness notifier ────────────────────────────────────────────────────────

@riverpod
class LivenessNotifier extends _$LivenessNotifier {
  late ChallengeManager _manager;

  Timer? _timeoutTimer;

  // Gesture signal histories — raw angle / probability ring buffers.
  // Not stored in state to avoid unnecessary rebuilds on every frame.
  final List<double> _xHistory = [];   // headEulerAngleX for nod detection
  final List<double> _earHistory = []; // eye open probability for blink
  static const int _historySize = 20;

  bool _challengeProcessing = false;

  @override
  LivenessState build() {
    final livenessConfig = ref.read(kycConfigProvider).livenessConfig;

    _manager = ChallengeManager(
      pool: livenessConfig?.challengePool,
      count: livenessConfig?.challengeCount ?? 2,
    );

    ref.onDispose(_cleanup);

    return const LivenessState();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Transitions from [LivenessPhase.loading] to [LivenessPhase.positioning].
  /// Call once the camera + ML Kit are ready.
  void startDetection() {
    if (state.phase != LivenessPhase.loading) return;
    state = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      totalCount: _manager.totalCount,
    );
  }

  /// Called for every camera frame that contains a detected face.
  /// [data] is the structured face attributes from [FaceDetectorService.detect].
  void processFrame(LivenessFaceData data) {
    if (!state.faceDetected && state.phase != LivenessPhase.complete) {
      state = state.copyWith(faceDetected: true);
    }

    // Check face size and update position guidance on every frame.
    _checkFacePosition(data.faceSizeRatio);

    switch (state.phase) {
      case LivenessPhase.positioning:
        // Only advance to challenges when the user is at the correct distance.
        if (state.positionGuidance == null) {
          _startNextChallenge();
        }
        return;

      case LivenessPhase.challenge:
        if (_challengeProcessing) return;
        // Suspend gesture detection while position is wrong — the face is
        // too far or too close for reliable classification.
        if (state.positionGuidance != null) return;
        _updateHistory(data);
        _checkGesture(data);

      default:
        return;
    }
  }

  /// Called when a camera frame produces no faces.
  void reportNoFace() {
    if (!state.faceDetected) return;
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    state = state.copyWith(
      faceDetected: false,
      clearPositionGuidance: true, // no face → no distance guidance
    );
  }

  /// Normalises exposure (lifts a backlit/dark face) and encodes a sharp selfie,
  /// base64-encodes it, and transitions to [LivenessPhase.complete]. Call from
  /// the screen after taking a picture. The work runs in an isolate / on a
  /// native thread, so it doesn't block the UI isolate.
  Future<void> captureSelfie(Uint8List imageBytes) async {
    if (state.phase != LivenessPhase.capturing) return;
    // Single pass: bake orientation, brighten a backlit/dark face, size + encode
    // a sharp JPEG (no square-box downscale that would soften the face).
    final bytes = await processSelfieImage(imageBytes);
    state = state.copyWith(
      phase: LivenessPhase.complete,
      selfieBase64: base64Encode(bytes),
      instruction: 'Verification complete',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// Resets the liveness session — picks a fresh random challenge set.
  void reset() {
    _cleanup();
    _manager.reset();
    _xHistory.clear();
    _earHistory.clear();
    _challengeProcessing = false;
    state = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      totalCount: _manager.totalCount,
    );
  }

  // ── Internal: face position check ─────────────────────────────────────────
  //
  // Mirrors gesture-detector.ts checkFacePosition() from the web SDK.
  // Thresholds: < 0.2 = too far, > 0.7 = too close.

  static const double _tooFarThreshold  = 0.20;
  static const double _tooCloseThreshold = 0.70;

  void _checkFacePosition(double faceSizeRatio) {
    // Don't override position guidance in terminal / transition phases.
    if (state.phase == LivenessPhase.challengePassed ||
        state.phase == LivenessPhase.capturing ||
        state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }

    final String? newGuidance;
    if (faceSizeRatio < _tooFarThreshold) {
      newGuidance = 'too_far';
    } else if (faceSizeRatio > _tooCloseThreshold) {
      newGuidance = 'too_close';
    } else {
      newGuidance = null;
    }

    if (newGuidance != state.positionGuidance) {
      if (newGuidance == null) {
        state = state.copyWith(clearPositionGuidance: true);
      } else {
        state = state.copyWith(positionGuidance: newGuidance);
      }
    }
  }

  // ── Internal: challenge transitions ───────────────────────────────────────

  void _startNextChallenge() {
    final challenge = _manager.current;
    if (challenge == null) {
      _cancelTimer();
      state = state.copyWith(
        phase: LivenessPhase.capturing,
        instruction: 'Hold still…',
        clearActiveChallenge: true,
        clearPositionGuidance: true,
      );
      return;
    }

    final livenessConfig = ref.read(kycConfigProvider).livenessConfig;
    final timeout =
        livenessConfig?.timeoutPerChallenge ?? challenge.timeoutSeconds;

    _xHistory.clear();
    _earHistory.clear();
    _challengeProcessing = false;

    state = state.copyWith(
      phase: LivenessPhase.challenge,
      instruction: challenge.instruction,
      timeoutRemaining: timeout,
      activeChallenge: challenge.type,
      clearPositionGuidance: true,
    );

    _startTimer(timeout);
  }

  void _checkGesture(LivenessFaceData data) {
    final challenge = _manager.current;
    if (challenge == null) return;

    final detected = switch (challenge.type) {
      LivenessChallenge.nod   => detectNod(_xHistory),
      LivenessChallenge.turn  => detectTurn(data.headEulerAngleY),
      LivenessChallenge.blink => detectBlink(_earHistory),
      LivenessChallenge.smile => detectSmile(data.smilingProbability),
    };

    if (detected) _onChallengePassed();
  }

  void _onChallengePassed() {
    _challengeProcessing = true;
    _cancelTimer();
    _manager.advance();

    state = state.copyWith(
      phase: LivenessPhase.challengePassed,
      instruction: 'Great!',
      completedCount: _manager.completedCount,
      timeoutRemaining: 0,
      clearPositionGuidance: true,
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (state.phase != LivenessPhase.challengePassed) return;
      _startNextChallenge();
    });
  }

  // ── Internal: signal history ───────────────────────────────────────────────

  void _updateHistory(LivenessFaceData data) {
    _xHistory.add(data.headEulerAngleX);
    if (_xHistory.length > _historySize) _xHistory.removeAt(0);

    _earHistory.add(data.eyeAverageOpenProbability);
    if (_earHistory.length > _historySize) _earHistory.removeAt(0);
  }

  // ── Internal: timeout timer ────────────────────────────────────────────────

  void _startTimer(int seconds) {
    _cancelTimer();
    var remaining = seconds;

    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        _onChallengeTimeout();
      } else {
        state = state.copyWith(timeoutRemaining: remaining);
      }
    });
  }

  void _cancelTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _onChallengeTimeout() {
    _cancelTimer();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Time\'s up. Please try again.',
      error: 'Challenge timed out',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  // ── Internal: cleanup ──────────────────────────────────────────────────────

  void _cleanup() {
    _cancelTimer();
  }
}
