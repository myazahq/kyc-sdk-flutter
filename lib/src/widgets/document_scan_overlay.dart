import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../services/document_framing_gate.dart';
import 'document_scan_painter.dart';

// ─── Document scan overlay ────────────────────────────────────────────────────
//
// Visual feedback for auto-capture. Deliberately elaborate: the wait before the
// shutter fires is real work (edge detection every frame, shape matching, a
// stability dwell), and with a bare guide box it reads as the camera being
// frozen. The motion is what makes "we are analysing this" legible.
//
// Each state maps to one question the user is actually asking:
//   searching   → "is the camera even working?"   → sweep + drifting grid
//   wrongShape  → "why won't it take the photo?"  → amber, motion stops
//   adjust      → "what do I do?"                 → amber, corners recede
//   holding     → "did it see it?"                → green lock-on + dwell ring
//   ready       → "is it done?"                   → full ring, flash

class DocumentScanOverlay extends StatefulWidget {
  final DocumentFraming framing;

  /// 0..1 through the stability dwell.
  final double progress;

  /// Guide rect aspect (width / height) the document should fill.
  final double aspect;

  const DocumentScanOverlay({
    super.key,
    required this.framing,
    required this.progress,
    required this.aspect,
  });

  @override
  State<DocumentScanOverlay> createState() => _DocumentScanOverlayState();
}

class _DocumentScanOverlayState extends State<DocumentScanOverlay>
    with TickerProviderStateMixin {
  // Sweep + grid drift: the "we're looking" motion.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  // Corner lock-on: a short, springy settle when the document is recognised,
  // so the transition reads as a decision rather than a colour swap.
  late final AnimationController _lock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  bool get _locked =>
      widget.framing == DocumentFraming.holding ||
      widget.framing == DocumentFraming.ready;

  @override
  void didUpdateWidget(covariant DocumentScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasLocked = oldWidget.framing == DocumentFraming.holding ||
        oldWidget.framing == DocumentFraming.ready;
    if (_locked && !wasLocked) {
      _lock.forward(from: 0);
    } else if (!_locked && wasLocked) {
      _lock.reverse();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final framing = widget.framing;

    // Amber for "I can see something, but it isn't right" — distinct from the
    // neutral searching state, so the user knows to act rather than wait.
    final needsAction = framing == DocumentFraming.wrongShape ||
        framing == DocumentFraming.adjust;
    final accent = _locked
        ? MyazaColors.success
        : needsAction
            ? MyazaColors.warning
            : colors.primary;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_sweep, _lock]),
        builder: (context, _) {
          final lock = Curves.easeOutBack.transform(
            _lock.value.clamp(0.0, 1.0),
          );
          return CustomPaint(
            painter: DocumentScanPainter(
              aspect: widget.aspect,
              accent: accent,
              // Freeze the search motion once locked: continuing to sweep
              // would imply we're still looking after we've decided.
              sweep: _locked ? null : _sweep.value,
              lock: lock,
              progress: widget.progress,
              // Only dim once we're confident — dimming while searching makes
              // a dark room impossible to aim in.
              scrim: _locked ? 0.45 : (needsAction ? 0.25 : 0.18),
              pulse: _locked
                  ? (math.sin(_sweep.value * math.pi * 4) + 1) / 2
                  : 0,
            ),
          );
        },
      ),
    );
  }
}
