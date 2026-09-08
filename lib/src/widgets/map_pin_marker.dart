import 'package:flutter/material.dart';

// ─── The Myaza map pin ───────────────────────────────────────────────────────
//
// The same drawing as the web SDK's MapPinMarker and the RN SDK's, so the
// built-in OSM picker wears the pin the framed Google map already does. A 1:1
// copy of the Bolt reference: head 46px, eye 0.31, stem 0.098 wide showing
// 0.41 below the head, no casings, flat body (no shadow on the pin itself).
//
// The GROUND DOT is the drag-state shadow: while the map pans the pin lifts
// 17px and the dot appears at the landing point beneath it; when the pin
// lands the dot goes, leaving the stem tip resting exactly on the picked
// coordinate. The parent aligns this widget's BOTTOM edge to the map centre.

const double kPinWidth = 46;
const double kPinHeight = 65;
const double kPinLift = 17;

class MapPinMarker extends StatelessWidget {
  /// The map is mid-pan: the pin floats and the landing dot shows.
  final bool lifted;

  /// The workflow's primary colour (the whole pin wears it).
  final Color color;

  const MapPinMarker({super.key, required this.lifted, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kPinWidth,
      height: kPinHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: -2.5,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: lifted ? 1 : 0,
              child: Container(
                width: 11,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF070330).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            offset: Offset(0, lifted ? -kPinLift / kPinHeight : 0),
            child: CustomPaint(
              size: const Size(kPinWidth, kPinHeight),
              painter: _PinPainter(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  final Color color;
  const _PinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20.75, 42, 4.5, 23),
        const Radius.circular(2.25),
      ),
      body,
    );
    canvas.drawCircle(const Offset(23, 23), 23, body);
    canvas.drawCircle(const Offset(23, 23), 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}
