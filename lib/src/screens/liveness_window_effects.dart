import 'package:flutter/material.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';

/// The soft shadow and coloured glow OUTSIDE the window. A box shadow would
/// also fall inside it and dim the face, so this paints with the window
/// itself clipped out.
class LivenessWindowGlow extends CustomPainter {
  const LivenessWindowGlow({required this.color});

  /// The frame's own colour: the brand while all is well, red on a warning.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide / 2),
    );
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(80))
        ..addRRect(window),
    );
    canvas.drawRRect(
      window,
      Paint()
        ..color = const Color(0x52000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      window.inflate(2),
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LivenessWindowGlow old) => old.color != color;
}

// ─── The scan ────────────────────────────────────────────────────────────────
//
// One pass of light down the window as the photo is taken. It is the shutter's
// follow-through, nothing more: nothing on the phone is examining the picture,
// so it is kept short enough not to look as if something were. It used to run
// down and back up over a second and a half, which held every person on the
// camera for that long after their photo was already taken.

const int kLivenessScanMs = 550;
const int _kScanDelayMs = 150;

/// How long the frame is held after the photo, full screen: the shutter, then
/// the scan, then a breath before the review.
const int kLivenessScanHoldMs = _kScanDelayMs + kLivenessScanMs + 100;

class LivenessScanSweep extends StatelessWidget {
  const LivenessScanSweep({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: const SizedBox.expand().animate().custom(
            delay: _kScanDelayMs.ms,
            duration: kLivenessScanMs.ms,
            curve: Curves.easeInOut,
            builder: (context, value, child) => CustomPaint(
              painter: _ScanPainter(value),
              child: child,
            ),
          ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  const _ScanPainter(this.t);

  /// 0 at the top of the window, 1 at the bottom.
  final double t;

  static const Color _light = MyazaColors.success;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final y = size.height * t;
    // The band of light trailing the line: what it has just passed over.
    const trail = 90.0;
    final band = Rect.fromLTRB(0, y - trail, size.width, y);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_light.withValues(alpha: 0), _light.withValues(alpha: 0.32)],
        ).createShader(band),
    );
    // The line itself: a soft glow under a bright core.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = _light.withValues(alpha: 0.9)
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}
