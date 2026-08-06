import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─── Passport illustration — vector marks ────────────────────────────────────
//
// Ports of the web SDK's inline SVGs (kyc-sdk-react
// src/components/PassportIllustration.tsx) so both SDKs draw the same screen.
// Each painter works in the source SVG's viewBox and scales to the widget, so
// the coordinates below can be compared against the web version line for line.

/// The international e-passport symbol (ICAO 9303), printed on the cover of
/// every chipped passport. It does more work here than a generic chip glyph: a
/// passport's chip is embedded with no visible contact pads, so this symbol is
/// what tells a holder the document can be read over NFC at all.
///
/// viewBox 24×16.
class EPassportMarkPainter extends CustomPainter {
  const EPassportMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 16);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final fill = Paint()..color = color;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.9, 0.9, 22.2, 14.2),
        const Radius.circular(2.2),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(7.6, 8), 1.7, fill);

    // The two radiating arcs.
    canvas.drawPath(
      Path()
        ..moveTo(11.4, 5.2)
        ..arcToPoint(const Offset(11.4, 10.8),
            radius: const Radius.circular(4.6), clockwise: true),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14.7, 3)
        ..arcToPoint(const Offset(14.7, 13),
            radius: const Radius.circular(8.4), clockwise: true),
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(EPassportMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A generic state emblem — a globe in a laurel wreath. Deliberately NOT any
/// real country's arms: the SDK verifies passports from every country, so this
/// stands in for all of them rather than showing a holder the wrong nation's
/// crest.
///
/// viewBox 48×48.
class StateEmblemPainter extends CustomPainter {
  const StateEmblemPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);

    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Globe — outline, meridian, and two parallels.
    canvas.drawCircle(const Offset(24, 21), 8.6, stroke(1.3));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(24, 21), width: 7, height: 17.2),
      stroke(1),
    );
    canvas.drawLine(const Offset(15.6, 18.4), const Offset(32.4, 18.4), stroke(1));
    canvas.drawLine(const Offset(15.6, 23.6), const Offset(32.4, 23.6), stroke(1));

    // Laurel wreath — the two sweeping branches.
    canvas.drawPath(
      Path()
        ..moveTo(17, 34)
        ..relativeCubicTo(-5, -2.6, -7.6, -7, -7.6, -12.4)
        ..relativeCubicTo(0, -2.4, 0.5, -4.6, 1.5, -6.6),
      stroke(1.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(31, 34)
        ..relativeCubicTo(5, -2.6, 7.6, -7, 7.6, -12.4)
        ..relativeCubicTo(0, -2.4, -0.5, -4.6, -1.5, -6.6),
      stroke(1.4),
    );

    // Leaves.
    const leaves = <List<double>>[
      [12.4, 19.6, 1.8, -0.4, 3.2, 0, 4.2, 1.2],
      [13.2, 25.4, 1.8, -0.2, 3.2, 0.4, 4, 1.7],
      [35.6, 19.6, -1.8, -0.4, -3.2, 0, -4.2, 1.2],
      [34.8, 25.4, -1.8, -0.2, -3.2, 0.4, -4, 1.7],
    ];
    for (final l in leaves) {
      canvas.drawPath(
        Path()
          ..moveTo(l[0], l[1])
          ..relativeCubicTo(l[2], l[3], l[4], l[5], l[6], l[7]),
        stroke(1.1),
      );
    }

    // Star finial — computed rather than transcribed, so it stays symmetrical.
    canvas.drawPath(_star(const Offset(24, 10.6), 4.6, 1.9), Paint()..color = color);
    canvas.restore();
  }

  Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(StateEmblemPainter oldDelegate) =>
      oldDelegate.color != color;
}
