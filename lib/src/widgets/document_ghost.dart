import 'dart:async';

import 'package:flutter/material.dart';

import '../config/document_guide.dart';

// ─── Document ghost ───────────────────────────────────────────────────────────
//
// A faint outline of the document's LAYOUT inside the capture guide, shown for
// a few seconds when the camera opens: where the portrait sits, where the
// printed details run, and — on a passport — the machine-readable band across
// the bottom.
//
// The guide rectangle says WHERE to put the document. It doesn't say which way
// round, and the commonest passport mistake is framing the page with the MRZ
// cropped off the bottom edge — which auto-capture then refuses, because that
// band is the chip's key and the proof the page is a passport.
//
// Drawn in the same language as PassportIllustration: placeholder BARS and
// BLOCKS, never literal drawings. An earlier version sketched a face from a
// circle and an arc, which is a worse thing to show a user than nothing at all.
// Nothing here is meant to be read — only recognised as a shape.
//
// Geometry comes from documentGuideRect, the same function the overlay and the
// post-shutter crop use, so the ghost cannot drift from the rectangle the user
// is aiming at.

/// How long the ghost stays before fading out. Long enough to register while
/// the user is still lifting the document into frame; short enough that it is
/// gone before it can obscure the document itself.
const Duration kDocumentGhostDuration = Duration(seconds: 5);

class DocumentGhost extends StatefulWidget {
  /// Guide aspect (width / height) — a card and a passport page differ.
  final double aspect;

  /// Draw the machine-readable band (passport data pages carry one).
  final bool showMrzBand;

  /// Hides the ghost early. Once a document is framed, the guidance has done
  /// its job and would only sit on top of the thing being captured.
  final bool documentFound;

  const DocumentGhost({
    super.key,
    required this.aspect,
    this.showMrzBand = false,
    this.documentFound = false,
  });

  @override
  State<DocumentGhost> createState() => _DocumentGhostState();
}

class _DocumentGhostState extends State<DocumentGhost> {
  bool _expired = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kDocumentGhostDuration, () {
      if (mounted) setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = !_expired && !widget.documentFound;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: CustomPaint(
          painter: _GhostPainter(
            aspect: widget.aspect,
            showMrzBand: widget.showMrzBand,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  final double aspect;
  final bool showMrzBand;

  const _GhostPainter({required this.aspect, required this.showMrzBand});

  // White rather than a theme token: this sits on a camera feed, not on a
  // surface, and the feed is the only thing behind it.
  static const _line = Color(0x4DFFFFFF); // 30%
  static const _fill = Color(0x1FFFFFFF); // 12%
  static const _band = Color(0x59FFFFFF); // 35%

  @override
  void paint(Canvas canvas, Size size) {
    final guide = documentGuideRect(size, aspect);
    if (guide.isEmpty) return;

    // Inset so the layout sits inside the document's edge, not on the guide.
    final pad = guide.width * 0.07;
    final page = Rect.fromLTRB(
      guide.left + pad,
      guide.top + pad,
      guide.right - pad,
      guide.bottom - pad,
    );

    final fill = Paint()..color = _fill;
    final band = Paint()..color = _band;

    // ── Portrait block ──────────────────────────────────────────────────────
    // A block, not a face. The proportion is what identifies it.
    final photoW = page.width * 0.24;
    final photoH = showMrzBand ? page.height * 0.46 : page.height * 0.58;
    final photo = Rect.fromLTWH(page.left, page.top, photoW, photoH);
    _rounded(canvas, photo, 4, fill);
    _rounded(
      canvas,
      photo,
      4,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Detail bars ─────────────────────────────────────────────────────────
    // Alternating lengths so it reads as printed fields rather than a barcode.
    final barLeft = photo.right + page.width * 0.06;
    final barMax = page.right - barLeft;
    const widths = [1.0, 0.62, 0.85, 0.5];
    final barH = (photo.height * 0.1).clamp(3.0, 7.0);
    for (var i = 0; i < widths.length; i++) {
      final y = photo.top + photo.height * (0.08 + i * 0.26);
      if (y + barH > photo.bottom) break;
      _rounded(
        canvas,
        Rect.fromLTWH(barLeft, y, barMax * widths[i], barH),
        barH / 2,
        fill,
      );
    }

    // ── MRZ band ────────────────────────────────────────────────────────────
    // The reason the ghost exists: it shows the band belongs INSIDE the frame,
    // which is the edge users most often crop away.
    if (showMrzBand) {
      final bandH = (page.height * 0.055).clamp(3.0, 8.0);
      final top = page.bottom - bandH * 3.2;
      for (var i = 0; i < 2; i++) {
        _rounded(
          canvas,
          Rect.fromLTWH(
            page.left,
            top + i * bandH * 1.9,
            page.width * (i == 0 ? 1.0 : 0.93),
            bandH,
          ),
          bandH / 2,
          band,
        );
      }
    }
  }

  void _rounded(Canvas canvas, Rect rect, double radius, Paint paint) =>
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.aspect != aspect || old.showMrzBand != showMrzBand;
}
