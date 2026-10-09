import 'dart:math' as math;
import 'dart:ui' show Size;

// ─── Is the face inside the window? ──────────────────────────────────────────
//
// In the sheet the camera circle shows the whole frame, so "the face is a
// sensible size in the frame" is the same statement as "the face sits in the
// circle". Full screen that stops being true: the frame fills the display and
// the window shows only its middle, so a face can be a fine size for the frame
// and still spill over the window's edge, or sit beside it. These rules judge
// the face against the WINDOW.
//
// Everything is in shares of the camera frame (0..1), which is what the face
// detector reports.

/// The window, as shares of the camera frame's width and height. Centred
/// across; [centreY] is where its middle sits down the frame (the window drops
/// a little below the centre on a short screen).
class FaceWindow {
  const FaceWindow({
    required this.width,
    required this.height,
    this.centreY = 0.5,
  });

  final double width;
  final double height;
  final double centreY;

  @override
  bool operator ==(Object other) =>
      other is FaceWindow &&
      other.width == width &&
      other.height == height &&
      other.centreY == centreY;

  @override
  int get hashCode => Object.hash(width, height, centreY);
}

/// A face wider than this share of the window is spilling over its edges.
const double kFaceWindowMaxFill = 0.84;

/// A face narrower than this share of the window is too far to judge.
const double kFaceWindowMinFill = 0.46;

/// How far the face's centre may sit from the window's, as a share of the
/// window's own width and height.
const double kFaceWindowMaxDrift = 0.2;

/// How much of the frame the window covers, and where its middle sits, for a
/// frame of [frameAspect] (width over height, upright) drawn cover-fit on a
/// [screen] with a window of [window] centred across and [drop] points below
/// the centre.
FaceWindow faceWindowFor({
  required Size screen,
  required Size window,
  required double frameAspect,
  double drop = 0,
}) {
  final shownWidth = math.max(screen.width, screen.height * frameAspect);
  final shownHeight = shownWidth / frameAspect;
  return FaceWindow(
    width: window.width / shownWidth,
    height: window.height / shownHeight,
    centreY: 0.5 + drop / shownHeight,
  );
}

/// What to ask of the person, or null when the face sits well in the window:
/// `too_close`, `too_far` or `off_centre`. Distance first: a face that is too
/// big cannot be centred into the window anyway.
///
/// [moving] is a turn or a nod in progress. The head is MEANT to leave the
/// centre then, and a turned face measures narrower, so only "too close"
/// stays strict; holding those gestures to the still rules would pause the
/// very movement being asked for.
String? faceWindowGuidance(
  FaceWindow window, {
  required double faceWidth,
  double? centreX,
  double? centreY,
  bool moving = false,
}) {
  if (faceWidth > window.width * kFaceWindowMaxFill) return 'too_close';
  final minFill = moving ? kFaceWindowMinFill / 2 : kFaceWindowMinFill;
  if (faceWidth < window.width * minFill) return 'too_far';
  if (moving) return null;
  // A detector that reports no centre cannot say the face has drifted.
  if (centreX != null &&
      (centreX - 0.5).abs() > window.width * kFaceWindowMaxDrift) {
    return 'off_centre';
  }
  if (centreY != null &&
      (centreY - window.centreY).abs() >
          window.height * kFaceWindowMaxDrift) {
    return 'off_centre';
  }
  return null;
}
