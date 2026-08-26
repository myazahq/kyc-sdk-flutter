import 'package:flutter/material.dart';

import '../config/theme.dart';

// The fast coarse gesture beside the exact box: dragging writes WHOLE numbers
// into the same field, and a register stake like 48.42 is still typed, because
// no thumb lands on it. Mirrors the RN SDK's OwnershipSlider and the web SDK's
// range input under the same box.
//
// Flutter ships a Slider, so this is the palette and the semantics rather than
// RN's hand-rolled PanResponder, which exists there only because importing a
// native slider module for one field was not worth it. Two details are carried
// over deliberately: NO tick marks and NO value bubble. Flutter draws both the
// moment `divisions` is set, and 100 of them turns a clean track into a ruler
// the RN and web sliders do not have.

/// The track and thumb sizes, from the RN component.
const double _track = 5;
const double _thumb = 22;

/// A primary disc inside a ring of the panel's own background, which is what
/// lifts it off the track. Flutter's stock thumb takes a colour but no border.
class _RingThumb extends SliderComponentShape {
  const _RingThumb({required this.ring, required this.fill});

  final Color ring;
  final Color fill;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_thumb / 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: _thumb / 2)),
      Colors.black,
      1.5,
      true,
    );
    canvas.drawCircle(center, _thumb / 2, Paint()..color = ring);
    canvas.drawCircle(center, _thumb / 2 - 3, Paint()..color = fill);
  }
}

class OwnershipSlider extends StatelessWidget {
  const OwnershipSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The current stake 0-100. An UNDECLARED one rests the thumb at 0, and only
  /// a drag writes a value, so an untouched slider still submits "not
  /// declared" rather than a confident zero.
  final double value;
  final void Function(double next) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: _track,
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.border,
        // The stock shapes leave a gap at each end; the RN track runs edge to
        // edge under the thumb.
        trackShape: const RectangularSliderTrackShape(),
        thumbShape: _RingThumb(ring: colors.background, fill: colors.primary),
        overlayColor: colors.primary.withValues(alpha: 0.12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        // Whole numbers WITHOUT the ruler: divisions is what draws 100 ticks.
        tickMarkShape: SliderTickMarkShape.noTickMark,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Semantics(
        label: 'Ownership percentage',
        value: '${value.round()}%',
        child: Slider(
          value: value.clamp(0, 100),
          max: 100,
          divisions: 100,
          onChanged: (next) => onChanged(next.roundToDouble()),
        ),
      ),
    );
  }
}
