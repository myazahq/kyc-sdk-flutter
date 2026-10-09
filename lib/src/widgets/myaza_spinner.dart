import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';

// THE loading spinner, everywhere in the SDK: the same hooked arc the web SDK
// and the dashboard spin (their `Loader2`, Hugeicons' Loading02), turning once
// a second.
//
// It replaces Material's CircularProgressIndicator, which is a different
// drawing from the one the web shows, and the pulsing ring some screens used.
// One flow should wait the same way on every surface an organisation puts it
// on.
//
// It sizes itself the way the Material indicator did: it fills the box it is
// given (every call site wraps it in a SizedBox) and is 36 across when the box
// is unbounded. [color], [strokeWidth] and [valueColor] are accepted so a
// screen swaps the class name and nothing else; the stroke is the icon's own.
//
// The PATH is copied from the icon, not redrawn: change it here and in the
// React Native SDK (components/spinnerShape.ts) together.

/// Hugeicons Loading02 (stroke rounded), on a 24 x 24 box.
const String kSpinnerPath =
    'M18.001 20C16.3295 21.2558 14.2516 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 12.8634 21.8906 13.7011 21.6849 14.5003C21.4617 15.3673 20.5145 15.77 19.6699 15.4728C18.9519 15.2201 18.6221 14.3997 18.802 13.66C18.9314 13.1279 19 12.572 19 12C19 8.13401 15.866 5 12 5C8.13401 5 5 8.13401 5 12C5 15.866 8.13401 19 12 19C13.3197 19 14.554 18.6348 15.6076 18';

/// The stroke the SDKs draw every icon at, on the 24-unit box.
const double kSpinnerStroke = 1.6;

/// One turn, as the web's `animate-spin`.
const Duration kSpinnerTurn = Duration(milliseconds: 1000);

/// The side of an unboxed spinner (the Material indicator's own default).
const double kSpinnerDefaultSize = 36;

/// The icon's outline as a [Path] on its 24 x 24 box. Only the absolute
/// `M` and `C` commands the icon uses are read.
Path spinnerPath([String data = kSpinnerPath]) {
  final path = Path();
  final tokens = RegExp(r'[MC]|-?\d*\.?\d+').allMatches(data).map((m) => m.group(0)!).toList();
  var i = 0;
  var command = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (tokens[i] == 'M' || tokens[i] == 'C') command = tokens[i++];
    if (command == 'M') {
      path.moveTo(next(), next());
    } else {
      path.cubicTo(next(), next(), next(), next(), next(), next());
    }
  }
  return path;
}

class MyazaSpinner extends StatefulWidget {
  /// Defaults to the flow's primary colour.
  final Color? color;

  /// Accepted for the Material indicator's call sites; [color] wins.
  final Animation<Color?>? valueColor;

  /// Accepted for the Material indicator's call sites and not used: the
  /// spinner is drawn at the icon's own stroke.
  final double? strokeWidth;

  const MyazaSpinner({super.key, this.color, this.valueColor, this.strokeWidth});

  @override
  State<MyazaSpinner> createState() => _MyazaSpinnerState();
}

class _MyazaSpinnerState extends State<MyazaSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: kSpinnerTurn)..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.color ?? widget.valueColor?.value ?? context.myazaColors.primary;
    return Semantics(
      label: 'Loading',
      child: LayoutBuilder(
        builder: (context, box) {
          final side = box.biggest.shortestSide.isFinite ? box.biggest.shortestSide : kSpinnerDefaultSize;
          return SizedBox(
            width: side,
            height: side,
            child: RotationTransition(
              turns: _turn,
              child: CustomPaint(painter: _SpinnerPainter(colour)),
            ),
          );
        },
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  static final Path _icon = spinnerPath();
  final Color colour;

  const _SpinnerPainter(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.scale(scale);
    canvas.drawPath(
      _icon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = kSpinnerStroke
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.colour != colour;
}
