import 'face_detection.dart';

// ─── Is the face straight enough to photograph? ──────────────────────────────
//
// The selfie is taken right after the last gesture. A turn or a nod leaves the
// head still coming back, and a fixed short pause was all that stood between
// the gesture and the photo, so the photo was often of a face mid-turn: no use
// as a record, and worse for the face match. The photo now waits until the
// face is looking at the camera and has stayed that way for a moment.

/// Left or right of the camera, degrees. A turn gesture needs 25. Yaw is the
/// one angle both platforms report against a true zero, so it is the one held
/// to an absolute limit.
const double kStraightYaw = 10;

/// How far any angle may move between two frames and the head still count as
/// at rest, degrees.
///
/// Pitch and roll are judged by REST, not by value. On iPhone they have no
/// dependable zero (roll carries the camera's orientation, pitch is often an
/// estimate from landmarks), so an absolute limit there was never met: every
/// photo then waited out the whole timeout, four seconds after "Hold still".
/// A nod that has stopped is a head at rest, whatever number it rests on.
const double kStraightMaxStep = 4;

/// How long the face has to stay straight and at rest before the photo.
const Duration kStraightHold = Duration(milliseconds: 300);

/// After this the photo is taken anyway: a person who cannot hold the pose
/// (or a detector that will not report one) must not be trapped on the camera.
const Duration kStraightTimeout = Duration(milliseconds: 2500);

/// How long to wait before SAYING "look straight": most faces settle by
/// themselves, and the words should not flash up for those.
const Duration kStraightPromptAfter = Duration(milliseconds: 700);

const String kLookStraightInstruction = 'Look straight at the camera';

/// Watches the frames before the photo. Feed each frame once; true once the
/// face has faced the camera, at rest, for [kStraightHold].
class StraightWatch {
  LivenessFaceData? _previous;
  DateTime? _since;

  bool update(LivenessFaceData data, DateTime now) {
    final previous = _previous;
    _previous = data;
    final facing = data.headEulerAngleY.abs() <= kStraightYaw;
    final atRest = previous != null &&
        (data.headEulerAngleY - previous.headEulerAngleY).abs() <=
            kStraightMaxStep &&
        (data.headEulerAngleX - previous.headEulerAngleX).abs() <=
            kStraightMaxStep &&
        (data.headEulerAngleZ - previous.headEulerAngleZ).abs() <=
            kStraightMaxStep;
    if (!facing || !atRest) {
      _since = null;
      return false;
    }
    final since = _since ??= now;
    return now.difference(since) >= kStraightHold;
  }
}
