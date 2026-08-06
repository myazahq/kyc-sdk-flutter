import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/document_guide.dart';

// ─── Document scan painter ────────────────────────────────────────────────────
//
// The drawing half of DocumentScanOverlay, split out for the 200-line rule.
// Layers, back to front: scrim → grid → sweep → brackets → dwell ring.

class DocumentScanPainter extends CustomPainter {
  final double aspect;
  final Color accent;

  /// 0..1 sweep phase, or null once locked (motion stops).
  final double? sweep;

  /// 0..1 corner lock-on settle.
  final double lock;

  /// 0..1 stability dwell.
  final double progress;

  /// Darkness outside the guide.
  final double scrim;

  /// 0..1 breathing pulse while locked.
  final double pulse;

  const DocumentScanPainter({
    required this.aspect,
    required this.accent,
    required this.sweep,
    required this.lock,
    required this.progress,
    required this.scrim,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _guideRect(size);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    _paintScrim(canvas, size, rrect);
    if (sweep != null) _paintGrid(canvas, rrect, sweep!);
    if (sweep != null) _paintSweep(canvas, rect, rrect, sweep!);
    _paintBorder(canvas, rrect);
    _paintBrackets(canvas, rect);
    if (progress > 0) _paintRing(canvas, rect);
  }

  /// Dim everything outside the guide so the eye goes to the document.
  void _paintScrim(Canvas canvas, Size size, RRect guide) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(guide),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: scrim),
    );
  }

  /// Faint drifting grid — reads as "processing", and gives the sweep
  /// something to travel over so motion is visible on a plain background.
  void _paintGrid(Canvas canvas, RRect guide, double phase) {
    canvas.save();
    canvas.clipRRect(guide);
    final rect = guide.outerRect;
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    const step = 26.0;
    final drift = phase * step; // one cell per cycle, so it loops seamlessly
    for (double x = rect.left - step + drift; x < rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    for (double y = rect.top - step + drift; y < rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    canvas.restore();
  }

  /// Scan line with a gradient trail, ping-ponging so it never jumps.
  void _paintSweep(Canvas canvas, Rect rect, RRect guide, double phase) {
    final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    final y = rect.top + rect.height * t;
    final band = Rect.fromLTWH(rect.left, y - 26, rect.width, 52);

    canvas.save();
    canvas.clipRRect(guide);
    // Soft trailing glow.
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    // Bright core line.
    final core = Rect.fromLTWH(rect.left, y - 1.5, rect.width, 3);
    canvas.drawRect(
      core,
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0),
          ],
        ).createShader(core),
    );
    canvas.restore();
  }

  /// Thin outline of the guide, so the target is visible before detection has
  /// anything to say.
  void _paintBorder(Canvas canvas, RRect guide) {
    canvas.drawRRect(
      guide,
      Paint()
        ..color = accent.withValues(alpha: 0.35 + 0.25 * lock)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// Corner brackets. They grow and thicken as [lock] settles, so recognition
  /// is felt rather than just coloured.
  void _paintBrackets(Canvas canvas, Rect rect) {
    final grow = 1 + 0.18 * lock;
    final arm = rect.width * 0.10 * grow;
    final width = 3 + 2 * lock + pulse * 0.8;

    final paint = Paint()
      ..color = accent.withValues(alpha: 0.7 + 0.3 * lock)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // A glow underlay once locked, so the brackets read as "engaged".
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.28 * lock)
      ..strokeWidth = width * 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    void corner(Offset origin, double dx, double dy) {
      final h = [origin, origin.translate(arm * dx, 0)];
      final v = [origin, origin.translate(0, arm * dy)];
      if (lock > 0) {
        canvas.drawLine(h[0], h[1], glow);
        canvas.drawLine(v[0], v[1], glow);
      }
      canvas.drawLine(h[0], h[1], paint);
      canvas.drawLine(v[0], v[1], paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  /// Dwell ring — turns the deliberate "hold still" wait into visible progress
  /// instead of an unexplained pause.
  void _paintRing(Canvas canvas, Rect rect) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(14)),
      );
    final ring = Paint()
      ..color = accent
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final clamped = progress.clamp(0.0, 1.0);
    for (final metric in path.computeMetrics()) {
      final drawn = metric.extractPath(0, metric.length * clamped);
      canvas.drawPath(drawn, glow);
      canvas.drawPath(drawn, ring);
    }

    // At completion, a brief full-frame flash sells the capture.
    if (clamped >= 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)),
        Paint()
          ..color = accent.withValues(alpha: 0.16 * (math.sin(pulse * math.pi))),
      );
    }
  }

  /// Shared with the post-shutter crop — see config/document_guide.dart. This
  /// painter must NOT compute its own rect: the user frames against what is
  /// drawn here, and the crop takes what that file defines.
  Rect _guideRect(Size size) => documentGuideRect(size, aspect);

  @override
  bool shouldRepaint(DocumentScanPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.lock != lock ||
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.scrim != scrim ||
      oldDelegate.pulse != pulse ||
      oldDelegate.aspect != aspect;
}
