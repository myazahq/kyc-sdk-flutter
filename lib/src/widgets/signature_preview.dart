import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/signature.dart';
import '../config/theme.dart';
import 'icons/icons.dart';
import 'signature_pad_parts.dart';

// ─── A signature that has been kept ──────────────────────────────────────────
//
// The drawing, small, and the row it sits in once saved: Edit reopens the pad
// with it, the cross removes it. Dark ink on a white tile in both themes, like
// the pad. Fitted to the ink rather than to the pad, so a small signature in
// one corner still fills the tile.
//
// The drawing lives only as long as the screen, so a resumed session has none
// and shows the pen mark instead. MIRRORS the web SDK's SignaturePreview and
// signed row, and the React Native ones.

const double _kTileWidth = 72;
const double _kTileHeight = 40;
const double _kTilePadding = 6;
const double _kTileInk = 1.5;

class SignaturePreview extends StatelessWidget {
  const SignaturePreview({super.key, required this.drawing});

  final SignatureDrawing drawing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Your signature',
      child: Container(
        width: _kTileWidth,
        height: _kTileHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD4D4D4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(painter: _PreviewPainter(drawing.strokes)),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    Rect? box;
    for (final stroke in strokes) {
      for (final p in stroke) {
        final at = Rect.fromLTWH(p.dx, p.dy, 0, 0);
        box = box == null ? at : box.expandToInclude(at);
      }
    }
    if (box == null) return;
    final width = math.max(box.width, 1.0);
    final height = math.max(box.height, 1.0);
    final scale = math.min(
      (size.width - 2 * _kTilePadding) / width,
      (size.height - 2 * _kTilePadding) / height,
    );
    // Centred in the tile, the web's `xMidYMid meet`.
    final dx = (size.width - width * scale) / 2 - box.left * scale;
    final dy = (size.height - height * scale) / 2 - box.top * scale;
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = _kTileInk;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      Offset fit(Offset p) => Offset(p.dx * scale + dx, p.dy * scale + dy);
      final path = Path()..moveTo(fit(stroke.first).dx, fit(stroke.first).dy);
      // A lone point is a dot: a zero-length line with round caps.
      if (stroke.length == 1) {
        path.lineTo(fit(stroke.first).dx, fit(stroke.first).dy);
      }
      for (final p in stroke.skip(1)) {
        path.lineTo(fit(p).dx, fit(p).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

class SignedSignatureRow extends StatelessWidget {
  const SignedSignatureRow({
    super.key,
    required this.drawing,
    required this.label,
    required this.onEdit,
    required this.onRemove,
  });

  final SignatureDrawing? drawing;
  final String label;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final drawing = this.drawing;
    return Container(
      padding: const EdgeInsets.only(left: MyazaSpacing.md, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Row(
        children: [
          if (drawing != null)
            SignaturePreview(drawing: drawing)
          else
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: MyazaIcon(
                MyazaIcons.penLine,
                size: 16,
                color: colors.primary,
              ),
            ),
          const SizedBox(width: MyazaSpacing.sm + 4),
          Expanded(
            child: Text(
              'Signed on screen',
              style: text.label.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            label: 'Edit $label',
            excludeSemantics: true,
            button: true,
            child: SignatureTextAction(
              label: 'Edit',
              icon: MyazaIcons.penLine,
              onPressed: onEdit,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove $label',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: MyazaIcon(MyazaIcons.x, size: 16, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
