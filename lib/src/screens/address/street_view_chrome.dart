import 'package:flutter/material.dart';

// ─── The framing chrome over the Street View panorama ────────────────────────
//
// A dimmed surround, a white rounded frame and the caption above it. A mirror
// of the web SDK's framer overlay (identical geometry, so hosted, embedded and
// native applicants meet the same instrument) and the RN StreetViewChrome.
// Ignores pointers throughout: the drag reaches the WebView.

/// The frame's rectangle inside a viewport: 58% wide (max 320), 56% tall
/// (max 300), centred horizontally, its centre 44% down.
Rect streetViewFrameRect(Size viewport) {
  final width = (viewport.width * 0.58).clamp(0.0, 320.0);
  final height = (viewport.height * 0.56).clamp(0.0, 300.0);
  return Rect.fromLTWH(
    (viewport.width - width) / 2,
    viewport.height * 0.44 - height / 2,
    width,
    height,
  );
}

class StreetViewChrome extends StatelessWidget {
  const StreetViewChrome({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(builder: (context, constraints) {
          final frame = streetViewFrameRect(constraints.biggest);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _DimPainter(frame))),
            Positioned.fromRect(
              rect: frame,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 2,
                  ),
                ),
              ),
            ),
            Positioned(
              top: frame.top - 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Fit your entrance in the frame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ]);
        }),
      );
}

/// Dims everything outside the frame (the web overlay's 9999px shadow).
class _DimPainter extends CustomPainter {
  final Rect frame;

  const _DimPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outside, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.frame != frame;
}
