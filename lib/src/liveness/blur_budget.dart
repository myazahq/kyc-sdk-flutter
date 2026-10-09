// ─── Can this phone afford the blur? ─────────────────────────────────────────
//
// The full-screen liveness camera blurs the live feed everywhere but the face
// window. A blur over a moving camera texture is redrawn on every frame, and
// on a slow phone it takes the frame budget the face detector also needs: the
// preview stutters and gestures are missed. So the screen watches how long its
// frames take to draw and, when too many are slow, gives the blur up for a
// flat tint. Once given up it stays given up: a screen that switched back and
// forth would be worse than either.

/// A frame drawn slower than this has missed a 60 Hz refresh.
const Duration kBlurSlowFrame = Duration(milliseconds: 18);

/// How many frames are judged at a time.
const int kBlurWindowFrames = 60;

/// The share of slow frames in one window that ends the blur.
const double kBlurSlowShare = 0.4;

/// The first frames after the camera opens are always slow (the texture and
/// the shaders are being set up) and say nothing about the phone.
const int kBlurWarmupFrames = 30;

/// Feed the draw time of each frame; [affordable] turns false, for good, once
/// a whole window had too many slow ones.
class BlurBudget {
  int _seen = 0;
  int _inWindow = 0;
  int _slow = 0;
  bool _affordable = true;

  bool get affordable => _affordable;

  /// Returns true when this frame is the one that ended the blur.
  bool add(Duration drawTime) {
    if (!_affordable) return false;
    _seen++;
    if (_seen <= kBlurWarmupFrames) return false;
    _inWindow++;
    if (drawTime > kBlurSlowFrame) _slow++;
    if (_inWindow < kBlurWindowFrames) return false;
    final tooSlow = _slow / _inWindow >= kBlurSlowShare;
    _inWindow = 0;
    _slow = 0;
    if (!tooSlow) return false;
    _affordable = false;
    return true;
  }
}
