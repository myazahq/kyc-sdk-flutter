import 'face_detection.dart';

// ─── Passive Liveness: the hold ──────────────────────────────────────────────
//
// Passive Liveness (`livenessMode: 'passive'`) asks for one prompt, hold: the
// face holds still in the circle for about two seconds while the clip records,
// then the selfie is taken and the server's liveness model decides.
//
// The web SDK counts 60 consecutive in-position frames at ~30 fps. Flutter's
// detector runs at a device-dependent rate (the native pipeline throttles
// frames), so a frame count would mean a different wait on every phone. The
// hold is measured in TIME instead, and still has to be CONSECUTIVE: it
// restarts whenever the face leaves position, and when frames stop arriving
// for longer than [PassiveHold.maxGap] (nothing vouched for that stretch).

/// About two seconds of a steady, centred face.
const Duration kPassiveHoldDuration = Duration(seconds: 2);

/// How far the face centre may sit from the middle of the frame, in normalised
/// frame units, and still count as centred. Generous on purpose: a symmetric
/// box around 0.5 holds whatever the detector's rotation or mirroring, and the
/// circle's size check already keeps the face in the frame.
const double kHoldCentreTolerance = 0.25;

/// Whether one frame counts toward the hold: centred (when the detector
/// reports a centre) and looking at the camera rather than turned away. The
/// caller has already checked the face size (too far / too close).
bool holdFrameInPosition(LivenessFaceData data) {
  final x = data.faceCenterX;
  final y = data.faceCenterY;
  final centred = (x == null || (x - 0.5).abs() <= kHoldCentreTolerance) &&
      (y == null || (y - 0.5).abs() <= kHoldCentreTolerance);
  return centred && !detectTurn(data.headEulerAngleY);
}

class PassiveHold {
  PassiveHold({
    this.duration = kPassiveHoldDuration,
    this.maxGap = const Duration(milliseconds: 600),
  });

  final Duration duration;

  /// The longest silence between frames the hold survives.
  final Duration maxGap;

  DateTime? _since;
  DateTime? _last;

  /// Feeds one frame; true once the face has been in position for [duration].
  bool update({required bool inPosition, required DateTime now}) {
    final last = _last;
    _last = now;
    if (!inPosition || (last != null && now.difference(last) > maxGap)) {
      _since = inPosition ? now : null;
      return false;
    }
    final since = _since ??= now;
    return now.difference(since) >= duration;
  }

  /// Starts the hold over (face lost, out of position, new challenge).
  void reset() {
    _since = null;
    _last = null;
  }
}
