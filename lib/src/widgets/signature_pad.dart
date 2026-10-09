import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../config/signature.dart';
import '../config/theme.dart';
import 'dashed_border.dart';
import 'signature_pad_parts.dart';

// ─── A box to sign in with a finger ──────────────────────────────────────────
//
// The pad is always white with dark ink, in both themes: it is a picture of ink
// on paper, and the image the server draws from these strokes looks the same.
// The strokes are kept as points and sent as points; nothing here rasterises a
// widget.
//
// A Listener (raw pointers) rather than a GestureDetector: a pan recogniser
// would lose the arena to the scrolling sheet this sits in, and the first few
// points of every stroke with it. The pad is wrapped in a vertical-drag
// absorber so the sheet does not scroll under a finger that is trying to sign.
//
// MIRRORS the web SDK's SignaturePad and the React Native one.

// The web pad's sizes: h-40, and min(60vh, 26rem) once expanded.
const double _kPadHeight = 160;

/// A bigger box for a long signature or a small phone.
const double _kPadHeightExpandedMax = 416;
const double _kPadHeightExpandedShare = 0.6;
const Duration _kResize = Duration(milliseconds: 200);
const Color _kInk = Color(0xFF111111);

class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.label,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
    this.enabled = true,
    this.initial,
  });

  /// Names the pad for a screen reader.
  final String label;

  /// Shown faintly until the first stroke.
  final String hint;
  final String clearLabel;
  final bool enabled;

  /// A signature to start from, when the person comes back to edit theirs.
  final SignatureDrawing? initial;

  /// Called after every stroke with the drawing so far.
  final ValueChanged<SignatureDrawing> onChanged;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  List<List<Offset>> _strokes = [];
  bool _expanded = false;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Size _size = Size.zero;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      // It arrives in the size of the pad it was drawn in; the first layout
      // fits it to this one.
      _strokes = [for (final stroke in initial.strokes) List.of(stroke)];
      _size = Size(initial.width, initial.height);
    }
  }

  int get _points => _strokes.fold(0, (sum, s) => sum + s.length);

  void _emit() {
    widget.onChanged(
      SignatureDrawing(
        strokes: [for (final s in _strokes) List.of(s)],
        width: _size.width,
        height: _size.height,
      ),
    );
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = e.pointer;
    setState(() => _strokes.add([e.localPosition]));
    _repaint.value++;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer ||
        _strokes.isEmpty ||
        _points >= kSignatureMaxPoints) {
      return;
    }
    final stroke = _strokes.last;
    // Skip sub-pixel jitter: it adds points and nothing to the line.
    if ((e.localPosition - stroke.last).distance < 1) return;
    stroke.add(e.localPosition);
    _repaint.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _emit();
  }

  void _clear() {
    setState(() => _strokes = []);
    _repaint.value++;
    _emit();
  }

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final empty = _strokes.isEmpty;
    final media = MediaQuery.of(context);
    final expandedHeight = math.min(
      media.size.height * _kPadHeightExpandedShare,
      _kPadHeightExpandedMax,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          image: true,
          label: widget.label,
          child: GestureDetector(
            // Claims vertical drags so the sheet behind does not scroll while signing.
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            child: CustomPaint(
              // Dashed, like the web pad's `border-2 border-dashed`.
              foregroundPainter: DashedRoundedBorder(
                color: colors.border,
                radius: MyazaRadius.sm,
                strokeWidth: 2,
              ),
              child: AnimatedContainer(
                duration: media.disableAnimations ? Duration.zero : _kResize,
                curve: Curves.easeOut,
                height: _expanded ? expandedHeight : _kPadHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MyazaRadius.sm),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final next = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          // Expanded, shrunk or rotated: keep what was signed, fitted
                          // to the new box. The painter reads the list on its next
                          // paint, which this very layout pass triggers.
                          final fitted = rescaleStrokes(_strokes, _size, next);
                          _size = next;
                          if (!identical(fitted, _strokes)) {
                            _strokes = fitted;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _emit();
                            });
                          }
                          return Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _down,
                            onPointerMove: _move,
                            onPointerUp: _up,
                            onPointerCancel: _up,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _SignaturePainter(
                                      () => _strokes,
                                      _repaint,
                                    ),
                                  ),
                                ),
                                // The line a signature sits on, and the prompt until there is one.
                                const Positioned(
                                  left: 24,
                                  right: 24,
                                  bottom: 36,
                                  child: IgnorePointer(
                                    child: SizedBox(
                                      height: 1,
                                      child: ColoredBox(
                                        color: Color(0xFFD4D4D4),
                                      ),
                                    ),
                                  ),
                                ),
                                if (empty)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 10,
                                    child: IgnorePointer(
                                      child: ExcludeSemantics(
                                        child: Text(
                                          widget.hint,
                                          textAlign: TextAlign.center,
                                          style: text.bodySmall.copyWith(
                                            color: const Color(0xFF737373),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // In the corner of the box itself, where the eye already is.
                    // Above the Listener in the stack, so a tap here never starts
                    // a stroke; always dark on the white pad.
                    Positioned(
                      top: 0,
                      right: 0,
                      child: SignatureExpandPill(
                        expanded: _expanded,
                        onTap: () => setState(() => _expanded = !_expanded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SignatureTextAction(
            label: widget.clearLabel,
            onPressed: widget.enabled && !empty ? _clear : null,
          ),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.read, Listenable repaint) : super(repaint: repaint);

  /// Read at paint time: a resize replaces the list.
  final List<List<Offset>> Function() read;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kInk
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.5, math.min(size.width, size.height) / 90);
    for (final stroke in read()) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        // A lone point is a dot.
        canvas.drawPoints(PointMode.points, stroke, paint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
