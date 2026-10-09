import 'dart:math' as math;
import 'dart:ui' show Size;

// The face window of the full-screen liveness camera: its size, from the box
// the camera is drawn in. Pure, so the layout and its tests share one rule.

const double kLivenessCutoutMaxWidth = 280;
const double kLivenessCutoutMinWidth = 200;

/// A face is taller than it is wide.
const double kLivenessCutoutAspect = 1.32;

/// The room above the window at which the gesture picture is drawn at its full
/// size (and, with 70 more, the long lighting note fits above it).
const double kLivenessRoomForGesture = 150;

/// The gesture picture's smallest side. Under this the drawing stops reading.
const double kLivenessGestureMinSize = 56;

/// What the instruction's pill and the gap under the picture take of the room.
const double kLivenessGesturePillRoom = 66;

/// The gesture picture at its full size, where there is the room for it.
const double kLivenessGestureFullSize = 96;

/// The side of the gesture picture for the room it has: from the top of the
/// back and close buttons (it stands between them) down to the window. The picture
/// ALWAYS stands on its own above the instruction: on a short phone it used to
/// move inside the instruction's pill, where it was 28 points across and easy
/// to miss beside the words. It now shrinks with the room instead, down to
/// [kLivenessGestureMinSize], and never past [full].
double livenessGestureSize(double room, double full) {
  final fit = (room - kLivenessGesturePillRoom).floorToDouble();
  return fit.clamp(kLivenessGestureMinSize, full < kLivenessGestureMinSize ? kLivenessGestureMinSize : full).toDouble();
}

/// The height of the block above the window. On a phone too short for even the
/// smallest picture and its instruction, the block keeps that height and runs
/// over the window's top edge (the hair, not the face) instead of shrinking
/// the picture further.
double livenessAboveHeight(double room) =>
    math.max(room, kLivenessGestureMinSize + kLivenessGesturePillRoom);

/// The face cutout: a tall rectangle whose ends are fully round. As wide as
/// the frame allows, and bounded by the height so the instruction above and
/// whatever sits below keep their room.
Size livenessCutout(Size frame) {
  final width = math
      .min(
        math.min(frame.width - 96, frame.height * 0.46 / kLivenessCutoutAspect),
        kLivenessCutoutMaxWidth,
      )
      .clamp(kLivenessCutoutMinWidth, kLivenessCutoutMaxWidth)
      .toDouble();
  return Size(width, width * kLivenessCutoutAspect);
}

// The window sits a little BELOW the centre on a short screen, and only by
// what the block above it is short of. That block is the gesture picture and
// the instruction. The picture is narrow and centred, so it rises into the gap
// BETWEEN the back and close buttons (LivenessImmersiveFrame); only the
// instruction, which is wide, has to stay under them. The window used to be
// dropped to fit the picture under the buttons too, which on a short phone
// pushed the face well below the middle and still left a small picture.
// The face is judged against the window wherever it sits (faceWindowFor takes
// the drop). Mirrors windowDrop in the web and React Native SDKs.

/// The room wanted above the window, from the top inset down: the gap over the
/// picture (8), the picture on its plate (108), the gap under it (8), the
/// instruction (46) and the gap over the window (20).
const double kLivenessWindowTopRoom = 190;

/// What must stay below the window: the gap under it, the retry panel a failed
/// check shows there (its words and its button), and the gap to the edge. It
/// was sized for the step count alone, and the panel was cut off.
const double kLivenessWindowBelowKeep = 136;

/// The furthest the window drops. More reads as off-centre.
const double kLivenessWindowMaxDrop = 48;

/// How far below the centre the window sits, for a frame and its window.
/// [topInset] is what the frame must keep clear of at its top (the status bar).
double livenessWindowDrop(Size frame, Size window, [double topInset = 0]) {
  final margin = (frame.height - window.height) / 2;
  final wanted = kLivenessWindowTopRoom + topInset - margin;
  final spare = margin - kLivenessWindowBelowKeep;
  final drop = math.min(math.min(wanted, spare), kLivenessWindowMaxDrop);
  return math.max(0.0, drop).roundToDouble();
}
