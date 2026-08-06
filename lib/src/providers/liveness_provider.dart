import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../liveness/challenge_manager.dart';
import '../liveness/face_detection.dart';
import '../liveness/flash_ready_gate.dart';
import '../liveness/face_continuity.dart';
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
  ///   'too_far'   → face width < 0.28 → "Kindly move closer"
  ///   'too_close' → face width > 0.7  → "Kindly move further away"
  ///   null        → correct distance
  /// Checked per-frame during positioning and challenge phases.
  /// Blocks challenge advancement when not null during positioning.
  final String? positionGuidance;

  /// True for a brief moment when the user performs a DIFFERENT gesture than the
  /// one requested (e.g. turning during a nod challenge). Drives the red-border +
  /// "Wrong gesture" feedback, mirroring the web SDK.
  final bool wrongGesture;

  /// True when more than one face is in frame. The challenge is paused and the
  /// user is asked to ensure only their face is visible (quality + anti-spoof).
  /// Mirrors the web SDK.
  final bool multipleFaces;

  /// Lighting guidance — null when lighting is acceptable, otherwise 'dark' or
  /// 'bright'. Blocks challenge start / auto-capture while non-null, mirroring
  /// the web SDK's lighting gate.
  final String? lightingGuidance;

  /// Flash-only "hold still" progress, 0..1 across the pre-flash dwell. 0 in
  /// gesture mode and whenever the hold hasn't started. Drives a subtle
  /// getting-ready ring so the flash never feels like it jumps out.
  final double flashReadyProgress;

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
    this.wrongGesture = false,
    this.multipleFaces = false,
    this.lightingGuidance,
    this.flashReadyProgress = 0,
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
    bool? wrongGesture,
    bool? multipleFaces,
    String? lightingGuidance,
    bool clearLightingGuidance = false,
    double? flashReadyProgress,
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
        wrongGesture: wrongGesture ?? this.wrongGesture,
        multipleFaces: multipleFaces ?? this.multipleFaces,
        lightingGuidance: clearLightingGuidance
            ? null
            : (lightingGuidance ?? this.lightingGuidance),
        flashReadyProgress: flashReadyProgress ?? this.flashReadyProgress,
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

  /// Shown once a flash-only face is framed + lit and the pre-flash hold begins.
  /// Doubles as the photosensitivity heads-up before the colours appear.
  static const String _kFlashHoldInstruction =
      'Hold still — the screen will flash briefly';

  bool _challengeProcessing = false;

  /// Tracks that the face performing the challenges is the face still in frame.
  /// Liveness without it proves a live human was present, not WHICH human.
  final _continuity = FaceContinuityGuard();

  /// Set when a second face appears at any point from the first challenge
  /// onwards, INCLUDING during capture. The flash runs in the capturing phase,
  /// so a guard that stops at capture stops exactly where the measurement that
  /// matters happens.
  bool _integrityBroken = false;

  /// True once the session can no longer vouch for who is in frame. The screen
  /// reads it to abort the flash rather than finish measuring a stranger.
  bool get integrityBroken => _integrityBroken;

  // Flash-only liveness: the pre-flash "hold still" gate (positioned + lit for a
  // dwell). Null in gesture / both modes, whose challenges already provide the
  // framing feedback loop. See FlashReadyGate.
  FlashReadyGate? _flashGate;

  // Whether the brightness sampler has produced at least one real reading.
  // Until it has, "no lighting warning" means UNKNOWN, not confirmed-good — so
  // the flash gate must not treat an unmeasured dim room as acceptable.
  bool _lightingSampled = false;

  @override
  LivenessState build() {
    final config = ref.read(kycConfigProvider);
    final livenessConfig = config.livenessConfig;

    // Flash-only liveness replaces the gesture challenges with the screen's
    // color sequence, so the state machine runs positioning → capturing and the
    // flash is performed at the capture seam (see LivenessScreen).
    final flashOnly = config.livenessMode == 'flash';
    _flashGate = flashOnly ? FlashReadyGate() : null;
    _manager = flashOnly
        ? ChallengeManager.none()
        : ChallengeManager(
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
    _continuity.reset();
    _integrityBroken = false;
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

    // More than one face — pause and ask for a single face (quality +
    // anti-spoofing). Auto-resumes when the frame returns to one face.
    if (data.faceCount > 1) {
      _onMultipleFaces();
      return;
    }
    if (state.multipleFaces) {
      _onSingleFaceRestored();
    }

    // Same face as a moment ago? Liveness proves a live human performed the
    // challenges; only continuity ties that human to the one being captured.
    switch (_continuity.update(data, DateTime.now())) {
      case FaceContinuity.substituted:
        _onFaceSubstituted();
        return;
      case FaceContinuity.reacquired:
        // Not proof of anything — people look away — but nothing vouches for
        // the returning face either, so earned progress does not cross the gap.
        _onFaceReacquired();
        return;
      case FaceContinuity.same:
        break;
    }

    // Check face size and update position guidance on every frame.
    _checkFacePosition(data.faceSizeRatio);

    switch (state.phase) {
      case LivenessPhase.positioning:
        final gate = _flashGate;
        if (gate != null) {
          _updateFlashReady(gate);
          return;
        }
        // Gesture / both: advance as soon as framed + lit — the challenges
        // themselves give the feedback and re-check framing. Flash-only can't
        // rely on that (nothing follows but the flash), so it runs the dwell
        // gate above instead.
        if (state.positionGuidance == null && state.lightingGuidance == null) {
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

  // ── Multiple faces ───────────────────────────────────────────────────────

  static const String multipleFacesGuidance =
      'Make sure only your face is visible';

  void _onMultipleFaces() {
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    // CAPTURING is deliberately NOT excused. The flash challenge runs in that
    // phase, so ignoring a second face there means the one measurement that
    // proves liveness is the one moment anybody may stand in frame. There is
    // no useful guidance to show mid-capture, so the session is marked broken
    // and the screen aborts the flash instead.
    if (state.phase == LivenessPhase.capturing) {
      _integrityBroken = true;
      return;
    }
    if (state.multipleFaces) return; // already paused
    // Pause the challenge timer so a second face can't run out the clock.
    _cancelTimer();
    // A second face invalidates the flash hold — restart it when we're back to
    // one, rather than resuming a hold that spanned two people.
    _flashGate?.reset();
    state = state.copyWith(
      multipleFaces: true,
      instruction: multipleFacesGuidance,
      wrongGesture: false,
      flashReadyProgress: 0,
    );
  }

  /// A different face is in frame. Nothing performed so far can be attributed
  /// to whoever is there now, so the session ends rather than continuing.
  void _onFaceSubstituted() {
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    _integrityBroken = true;
    // Mid-capture the verdict is recorded but NOT shown. The flash paints a
    // full-screen overlay with a hole cut at the preview circle's rect,
    // measured once when the flash starts; changing the phase here re-lays out
    // the screen underneath it, the circle moves, and the hole ends up over
    // nothing. The screen aborts the flash on this flag and reports the failure
    // once the overlay is gone.
    if (state.phase == LivenessPhase.capturing) return;
    _cancelTimer();
    _flashGate?.reset();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Let\'s start over — please stay in frame.',
      error: 'face_swap',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// Surfaces a failure that was detected mid-flash and deliberately withheld.
  ///
  /// Called by the screen once the flash overlay has been removed, so the
  /// re-layout happens against a plain screen rather than shifting the preview
  /// circle out from under the overlay's cutout.
  void reportIntegrityFailure() {
    if (!_integrityBroken) return;
    if (state.phase == LivenessPhase.complete) return;
    _cancelTimer();
    _flashGate?.reset();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Let\'s start over — please stay in frame.',
      error: 'face_swap',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// The face came back after being away. Restart from positioning: the
  /// challenges already passed were passed by a face nothing can now vouch for.
  void _onFaceReacquired() {
    if (state.phase != LivenessPhase.challenge &&
        state.phase != LivenessPhase.positioning) {
      if (state.phase == LivenessPhase.capturing) _integrityBroken = true;
      return;
    }
    _cancelTimer();
    _flashGate?.reset();
    _manager.reset();
    _xHistory.clear();
    _earHistory.clear();
    _challengeProcessing = false;
    state = state.copyWith(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      completedCount: 0,
      clearActiveChallenge: true,
      flashReadyProgress: 0,
    );
  }

  void _onSingleFaceRestored() {
    final resumeChallenge = state.phase == LivenessPhase.challenge;
    state = state.copyWith(multipleFaces: false);
    if (resumeChallenge) {
      final challenge = _manager.current;
      if (challenge != null) {
        // Reset gesture history and restart the (paused) challenge timer.
        _xHistory.clear();
        _earHistory.clear();
        _challengeProcessing = false;
        final timeout =
            ref.read(kycConfigProvider).livenessConfig?.timeoutPerChallenge ??
                challenge.timeoutSeconds;
        state = state.copyWith(instruction: challenge.instruction);
        _startTimer(timeout);
      }
    }
  }

  // ── Lighting gate ────────────────────────────────────────────────────────

  /// Feeds live lighting quality into the state machine. [guidance] is 'dark',
  /// 'bright', or null (acceptable). While non-null during positioning, the
  /// flow won't start challenges — discouraging capture in poor light.
  void setLightingGuidance(String? guidance) {
    // The screen only calls this after a genuine brightness reading, so the
    // first call is proof lighting has been measured — which the flash gate
    // needs to tell "confirmed OK" apart from "not yet checked".
    _lightingSampled = true;
    if (guidance == state.lightingGuidance) return;
    // Lighting guidance is only meaningful before/while capturing the selfie.
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed ||
        state.phase == LivenessPhase.capturing) {
      if (state.lightingGuidance != null) {
        state = state.copyWith(clearLightingGuidance: true);
      }
      return;
    }
    if (guidance == null) {
      state = state.copyWith(clearLightingGuidance: true);
    } else {
      state = state.copyWith(lightingGuidance: guidance);
    }
  }

  /// Called when a camera frame produces no faces.
  void reportNoFace() {
    _continuity.reportNoFace();
    if (!state.faceDetected) return;
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    // Losing the face breaks the flash hold — it must be re-earned when the
    // face returns, not resumed. (reportNoFace clears positionGuidance, which
    // would otherwise leave `framed` true with no face in the gate.)
    _flashGate?.reset();
    state = state.copyWith(
      faceDetected: false,
      clearPositionGuidance: true, // no face → no distance guidance
      multipleFaces: false, // no face → certainly not multiple
      flashReadyProgress: 0,
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
    _completeWithSelfie(bytes);
  }

  /// Like [captureSelfie] but for an already-enhanced/encoded JPEG (e.g. from the
  /// stream-frame fast path, where the worker already ran the selfie pipeline).
  /// Skips re-processing and just stores it.
  void captureSelfieEncoded(Uint8List jpegBytes) {
    if (state.phase != LivenessPhase.capturing) return;
    _completeWithSelfie(jpegBytes);
  }

  void _completeWithSelfie(Uint8List jpegBytes) {
    state = state.copyWith(
      phase: LivenessPhase.complete,
      selfieBase64: base64Encode(jpegBytes),
      instruction: 'Verification complete',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// Resets the liveness session — picks a fresh random challenge set.
  void reset() {
    _cleanup();
    _manager.reset();
    _flashGate?.reset();
    // A retry starts a fresh session: whoever is in frame now becomes the
    // reference, and the previous attempt's verdict does not carry over.
    _continuity.reset();
    _integrityBroken = false;
    // NOT _lightingSampled — the sampler keeps running across a retry, so
    // lighting stays confirmed; re-arming it would re-introduce the warmup race.
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
  // Thresholds: < 0.28 = too far, > 0.7 = too close. 0.28 (raised from 0.2) so a
  // clearly-distant face is prompted to move closer instead of slipping through
  // — kept in lockstep with the web SDK's MIN_FACE_WIDTH.
  static const double _tooFarThreshold  = 0.28;
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

  /// Flash-only pre-flash gate: hold a framed + lit face for a short dwell,
  /// then flash. Keeps the "come closer / more light" guidance visible the
  /// whole time and shows a "hold still" beat, so the flash never fires off a
  /// single frame or before lighting has actually been measured.
  void _updateFlashReady(FlashReadyGate gate) {
    final framed = state.positionGuidance == null;
    final lit = state.lightingGuidance == null;
    final result = gate.update(
      framed: framed,
      lit: lit,
      lightingConfirmed: _lightingSampled,
      now: DateTime.now(),
    );

    if (result.ready) {
      state = state.copyWith(flashReadyProgress: 1);
      _startNextChallenge(); // → capturing → flash
      return;
    }

    // Only overwrite the instruction while the face is actually framed + lit;
    // otherwise leave the position/lighting guidance to speak for itself.
    final instruction = (framed && lit) ? _kFlashHoldInstruction : state.instruction;
    if (state.flashReadyProgress != result.progress ||
        state.instruction != instruction) {
      state = state.copyWith(
        flashReadyProgress: result.progress,
        instruction: instruction,
      );
    }
  }

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
      wrongGesture: false,
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

    if (detected) {
      _onChallengePassed();
      return;
    }

    // Wrong-gesture feedback (mirrors the web SDK): the requested gesture wasn't
    // detected, but the user is clearly doing a DIFFERENT one. Flash a red
    // border + "Wrong gesture". The "wrong" signals per challenge avoid
    // self-overlap (e.g. a turn challenge doesn't flag turning as wrong).
    final isTurning = detectTurn(data.headEulerAngleY);
    final isSmiling = detectSmile(data.smilingProbability);
    final wrong = switch (challenge.type) {
      LivenessChallenge.nod   => isTurning || isSmiling,
      LivenessChallenge.turn  => isSmiling,
      LivenessChallenge.blink => isTurning || isSmiling,
      LivenessChallenge.smile => isTurning,
    };

    if (wrong != state.wrongGesture) {
      state = state.copyWith(wrongGesture: wrong);
    }
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
      wrongGesture: false,
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
