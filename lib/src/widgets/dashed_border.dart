import 'package:flutter/material.dart';

// ─── Dashed rounded border ────────────────────────────────────────────────────
//
// The web SDK's `border-dashed` cards (upload slots, hint boxes). Flutter has
// no dashed BoxBorder, so this painter draws one; wrap the child in a
// CustomPaint. Radius/stroke mirror the web's rounded-xl (12) and border-2.

class DashedRoundedBorder extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const DashedRoundedBorder({
    required this.color,
    required this.radius,
    this.strokeWidth = 1,
    this.dash = 5,
    this.gap = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRoundedBorder oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
