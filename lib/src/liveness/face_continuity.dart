import 'face_detection.dart';

// ─── Face continuity ──────────────────────────────────────────────────────────
//
// "Is this the same face it was a moment ago?"
//
// Liveness proves a live human performed the challenges. It proves nothing
// about WHO unless the face that performed them is the face that gets captured
// — otherwise one person can nod and blink while another is photographed, and
// every gesture check passes on the wrong person.
//
// Nothing here identifies anyone. It tracks whether the face in frame is
// CONTINUOUS with the one before it, which is all that is needed to reject a
// substitution:
//
//   • a jump — the face leaps across the frame or changes size abruptly.
//     Real heads move continuously at 15–30fps; a cut to another person does
//     not.
//   • a gap — the face left and a different one arrived. After a loss nothing
//     can vouch that the returning face is the same person, so progress earned
//     before the gap is not carried across it.
//   • a changed tracking id, where the platform provides one (Android ML Kit;
//     iOS Vision has no cross-frame equivalent). Proof rather than inference,
//     so it is used when present and never depended upon.
//
// Pure logic — no camera, no plugin — so the thresholds are testable.

/// What continuity checking concluded about the latest frame.
enum FaceContinuity {
  /// Same face, still tracked.
  same,

  /// A different face. The session cannot carry on: whoever performed the
  /// challenges is not who is in frame now.
  substituted,

  /// The face returned after being absent. Not proof of substitution — people
  /// look away — but nothing vouches for it either, so anything already earned
  /// must be re-earned.
  reacquired,
}

class FaceContinuityGuard {
  /// How far the face centre may travel between consecutive frames, as a share
  /// of the frame. Generous: at 15fps a real head can cover ground, and the
  /// cost of a false positive is a user being told to start again.
  final double maxCentreJump;

  /// Largest allowed frame-to-frame change in face size, as a ratio. A face
  /// that suddenly measures 1.6× its previous size is a different face, not
  /// someone leaning in.
  final double maxSizeRatioChange;

  /// A gap longer than this means the returning face is unvouched for. Short
  /// enough to catch a camera pan between two people, long enough to survive
  /// the dropped frames a colour flash causes.
  final Duration maxGap;

  FaceContinuityGuard({
    this.maxCentreJump = 0.35,
    this.maxSizeRatioChange = 1.6,
    this.maxGap = const Duration(milliseconds: 900),
  });

  double? _centreX;
  double? _centreY;
  double? _size;
  int? _trackingId;
  DateTime? _lastSeen;

  /// Forget everything — call when the flow restarts and the previous face is
  /// no longer the reference.
  void reset() {
    _centreX = null;
    _centreY = null;
    _size = null;
    _trackingId = null;
    _lastSeen = null;
  }

  /// Records that no face was visible in this frame.
  void reportNoFace() {
    // The position is kept: it is the comparison point for whatever comes back,
    // and _lastSeen ageing is what turns an absence into a gap.
  }

  /// Feeds a frame and reports what it means for continuity.
  FaceContinuity update(LivenessFaceData data, DateTime now) {
    final lastSeen = _lastSeen;
    final prevX = _centreX;
    final prevY = _centreY;
    final prevSize = _size;
    final prevTrack = _trackingId;

    _lastSeen = now;
    _centreX = data.faceCenterX;
    _centreY = data.faceCenterY;
    _size = data.faceSizeRatio;
    if (data.trackingId != null && data.trackingId! >= 0) {
      _trackingId = data.trackingId;
    }

    // Nothing to compare against yet.
    if (lastSeen == null) return FaceContinuity.same;

    // A tracking id that changed is proof, where the platform offers one.
    if (prevTrack != null &&
        data.trackingId != null &&
        data.trackingId! >= 0 &&
        data.trackingId != prevTrack) {
      return FaceContinuity.substituted;
    }

    // A gap: the face was away long enough that nothing vouches for its return.
    if (now.difference(lastSeen) > maxGap) return FaceContinuity.reacquired;

    // A jump: continuous frames, discontinuous face.
    if (prevX != null &&
        prevY != null &&
        data.faceCenterX != null &&
        data.faceCenterY != null) {
      final dx = (data.faceCenterX! - prevX).abs();
      final dy = (data.faceCenterY! - prevY).abs();
      if (dx > maxCentreJump || dy > maxCentreJump) {
        return FaceContinuity.substituted;
      }
    }

    if (prevSize != null && prevSize > 0.01 && data.faceSizeRatio > 0.01) {
      final ratio = data.faceSizeRatio / prevSize;
      if (ratio > maxSizeRatioChange || ratio < 1 / maxSizeRatioChange) {
        return FaceContinuity.substituted;
      }
    }

    return FaceContinuity.same;
  }
}
