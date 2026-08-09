import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The drawing half of the NFC scan illustration — see
/// `nfc_scan_illustration.dart` for the widget and the parity contract.
/// Every coordinate is the web SDK's, digit for digit, in its 320×240 space;
/// the canvas is scaled so the geometry never has to be re-derived here.

const nfcScanCoupling = Offset(173, 88);

/// (radius, base opacity, animation delay ms) — one entry per field ripple.
const nfcScanWaves = [
  (16.0, 0.9, 0),
  (28.0, 0.65, 150),
  (40.0, 0.42, 300),
  (50.0, 0.25, 450),
];

const _spreadDeg = 56.0;
const _periodMs = 1800.0;

/// Web keyframes: 0% .25 → 45% 1 → 100% .25, ease-in-out both ways.
double nfcWavePulse(double controllerValue, int delayMs) {
  var p = (controllerValue * _periodMs - delayMs) % _periodMs / _periodMs;
  if (p < 0) p += 1;
  if (p < 0.45) {
    return 0.25 + 0.75 * Curves.easeInOut.transform(p / 0.45);
  }
  return 1 - 0.75 * Curves.easeInOut.transform((p - 0.45) / 0.55);
}

class NfcScanPainter extends CustomPainter {
  final MyazaColorScheme colors;
  final Animation<double> pulse;
  final bool reduceMotion;

  NfcScanPainter({
    required this.colors,
    required this.pulse,
    required this.reduceMotion,
  }) : super(repaint: pulse);

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w, {StrokeCap cap = StrokeCap.butt}) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = cap;

  void _rotated(Canvas canvas, Offset pivot, double deg, VoidCallback draw) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    draw();
    canvas.restore();
  }

  /// Flutter has no dash API — segments drawn by hand, round-capped so the
  /// texture matches the pill-shaped ghost bars.
  void _dashes(Canvas canvas, Paint paint, Offset start, double len, double on, double off) {
    var x = start.dx;
    final end = start.dx + len;
    while (x < end) {
      canvas.drawLine(Offset(x, start.dy), Offset(math.min(x + on, end), start.dy), paint);
      x += on + off;
    }
  }

  void _document(Canvas canvas) {
    _rotated(canvas, const Offset(212, 112), 7, () {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(154, 30, 114, 164), const Radius.circular(10)),
        _fill(colors.backgroundSecondary.withValues(alpha: 0.5)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(154, 30, 114, 164), const Radius.circular(10)),
        _stroke(colors.border, 2),
      );

      // Portrait, top-right — an outline glyph floating in its frame.
      final photo =
          RRect.fromRectAndRadius(const Rect.fromLTWH(224, 46, 32, 42), const Radius.circular(6));
      canvas.drawRRect(photo, _fill(colors.textDark.withValues(alpha: 0.10)));
      canvas.drawRRect(photo, _stroke(colors.border, 1.5));
      final person = _stroke(
        colors.textSecondary.withValues(alpha: 0.5),
        2,
        cap: StrokeCap.round,
      );
      canvas.drawCircle(const Offset(240, 61), 5.5, person);
      canvas.drawPath(
        Path()
          ..moveTo(231.5, 77.5)
          ..arcToPoint(const Offset(248.5, 77.5), radius: const Radius.circular(8.5)),
        person,
      );

      // The chip — centred on the card, below the fan's lowest reach.
      final chip = RRect.fromRectAndRadius(
        const Rect.fromLTWH(200.5, 133, 21, 16),
        const Radius.circular(3),
      );
      canvas.drawRRect(chip, _fill(colors.textDark.withValues(alpha: 0.10)));
      final chipStroke = _stroke(colors.textSecondary.withValues(alpha: 0.7), 1.5);
      canvas.drawRRect(chip, chipStroke);
      canvas.drawLine(const Offset(200.5, 138.3), const Offset(221.5, 138.3), chipStroke);
      canvas.drawLine(const Offset(200.5, 143.7), const Offset(221.5, 143.7), chipStroke);
      canvas.drawLine(const Offset(211, 138.3), const Offset(211, 143.7), chipStroke);

      // The MRZ, low on the card, in the border tone.
      final mrz = _stroke(colors.border, 3, cap: StrokeCap.round);
      _dashes(canvas, mrz, const Offset(170, 174), 84, 6, 4);
      final mrz2 = _stroke(colors.border.withValues(alpha: 0.7), 3, cap: StrokeCap.round);
      _dashes(canvas, mrz2, const Offset(166, 184), 88, 4, 5);
    });
  }

  void _phone(Canvas canvas) {
    canvas.save();
    canvas.translate(12, 0);
    _rotated(canvas, const Offset(112, 126), -5, () {
      final nub = _fill(colors.textDark.withValues(alpha: 0.25));
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(57, 84, 3, 14), const Radius.circular(1.5)),
        nub,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(57, 103, 3, 14), const Radius.circular(1.5)),
        nub,
      );

      // Opaque base + tint, so the card can never ghost through the glass.
      final body =
          RRect.fromRectAndRadius(const Rect.fromLTWH(60, 30, 104, 192), const Radius.circular(24));
      canvas.drawRRect(body, _fill(colors.background));
      canvas.drawRRect(body, _fill(colors.backgroundSecondary.withValues(alpha: 0.4)));
      canvas.drawRRect(body, _stroke(colors.textDark.withValues(alpha: 0.25), 2));

      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(99, 46, 26, 8), const Radius.circular(4)),
        nub,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(87, 170, 50, 5), const Radius.circular(2.5)),
        _fill(colors.border),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(96, 181, 32, 4), const Radius.circular(2)),
        _fill(colors.border.withValues(alpha: 0.6)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(97, 205, 30, 3.5), const Radius.circular(1.75)),
        _fill(colors.textDark.withValues(alpha: 0.20)),
      );
    });
    canvas.restore();
  }

  void _field(Canvas canvas) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          colors.primary.withValues(alpha: 0.18),
          colors.primary.withValues(alpha: 0.06),
          colors.primary.withValues(alpha: 0),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: nfcScanCoupling, radius: 90));
    canvas.drawCircle(nfcScanCoupling, 90, glow);
    canvas.drawCircle(nfcScanCoupling, 4.5, _fill(colors.primary));

    for (final (r, base, delay) in nfcScanWaves) {
      final opacity = base * (reduceMotion ? 1 : nfcWavePulse(pulse.value, delay));
      canvas.drawArc(
        Rect.fromCircle(center: nfcScanCoupling, radius: r),
        -_spreadDeg * math.pi / 180,
        2 * _spreadDeg * math.pi / 180,
        false,
        _stroke(colors.primary.withValues(alpha: opacity), 3.25, cap: StrokeCap.round),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 320);
    _document(canvas);
    _phone(canvas);
    _field(canvas);
  }

  @override
  bool shouldRepaint(NfcScanPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.reduceMotion != reduceMotion;
}
