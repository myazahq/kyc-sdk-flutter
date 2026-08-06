import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';

// ─── Gallery-photo cropper ────────────────────────────────────────────────────
//
// Shown after "Upload a photo instead": an interactive ID-card crop box over the
// picked image, so a gallery photo arrives at the same framing the camera's
// guide would have produced.

class _CropParams {
  final Uint8List bytes;
  final int srcX;
  final int srcY;
  final int srcW;
  final int srcH;

  const _CropParams({
    required this.bytes,
    required this.srcX,
    required this.srcY,
    required this.srcW,
    required this.srcH,
  });
}

// Top-level so compute() can run it in a separate isolate.
Uint8List _doCropImage(_CropParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) throw Exception('Could not decode image');
  final baked = img.bakeOrientation(decoded);
  final sw = p.srcW.clamp(1, baked.width - p.srcX);
  final sh = p.srcH.clamp(1, baked.height - p.srcY);
  final cropped = img.copyCrop(baked, x: p.srcX, y: p.srcY, width: sw, height: sh);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

// ─── Crop handle ──────────────────────────────────────────────────────────────

enum _CropHandle { none, move, tl, tr, bl, br }

// ─── Document cropper screen ──────────────────────────────────────────────────

class DocumentCropperScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const DocumentCropperScreen({super.key, required this.imageBytes});

  @override
  State<DocumentCropperScreen> createState() => _DocumentCropperScreenState();
}

class _DocumentCropperScreenState extends State<DocumentCropperScreen> {
  // ISO/IEC 7810 ID-1 standard: 85.6 mm × 53.98 mm → AR ≈ 1.5858
  static const double _idAR = 85.6 / 53.98;

  Size? _naturalSize;
  Rect _imgRect = Rect.zero;
  Rect _cropRect = Rect.zero;
  bool _cropInitialized = false;
  bool _isProcessing = false;

  _CropHandle _handle = _CropHandle.none;
  Offset _panStart = Offset.zero;
  Rect _cropAtPanStart = Rect.zero;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadNaturalSize();
  }

  Future<void> _loadNaturalSize() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    if (mounted) setState(() => _naturalSize = size);
  }

  // ── Geometry helpers ─────────────────────────────────────────────────────

  /// Returns the rect of the rendered image (object-contain) within [container].
  Rect _computeImgRect(Size container) {
    if (_naturalSize == null) return Rect.zero;
    final natAR = _naturalSize!.width / _naturalSize!.height;
    final conAR = container.width / container.height;
    final double rw, rh;
    if (natAR > conAR) {
      rw = container.width;
      rh = container.width / natAR;
    } else {
      rh = container.height;
      rw = container.height * natAR;
    }
    return Rect.fromLTWH(
      (container.width - rw) / 2,
      (container.height - rh) / 2,
      rw,
      rh,
    );
  }

  /// Initial crop box: 85% of image width, centered, respecting ID AR.
  Rect _initCropRect(Rect imgRect) {
    double cropW = imgRect.width * 0.85;
    double cropH = cropW / _idAR;
    if (cropH > imgRect.height * 0.9) {
      cropH = imgRect.height * 0.9;
      cropW = cropH * _idAR;
    }
    return Rect.fromLTWH(
      imgRect.left + (imgRect.width - cropW) / 2,
      imgRect.top + (imgRect.height - cropH) / 2,
      cropW,
      cropH,
    );
  }

  /// Clamps the crop rect to stay within [bounds], maintaining _idAR.
  Rect _clampCrop(Rect crop, Rect bounds) {
    double w = crop.width.clamp(60.0, bounds.width);
    double h = w / _idAR;
    if (h > bounds.height) {
      h = bounds.height;
      w = h * _idAR;
      if (w > bounds.width) {
        w = bounds.width;
        h = w / _idAR;
      }
    }
    final maxLeft = (bounds.right - w).clamp(bounds.left, bounds.right);
    final maxTop  = (bounds.bottom - h).clamp(bounds.top, bounds.bottom);
    return Rect.fromLTWH(
      crop.left.clamp(bounds.left, maxLeft),
      crop.top.clamp(bounds.top, maxTop),
      w,
      h,
    );
  }

  // ── Gesture handling ─────────────────────────────────────────────────────

  _CropHandle _hitTest(Offset pos) {
    const double r = 28.0;
    if ((pos - _cropRect.topLeft).distance     < r) return _CropHandle.tl;
    if ((pos - _cropRect.topRight).distance    < r) return _CropHandle.tr;
    if ((pos - _cropRect.bottomLeft).distance  < r) return _CropHandle.bl;
    if ((pos - _cropRect.bottomRight).distance < r) return _CropHandle.br;
    if (_cropRect.inflate(8).contains(pos)) return _CropHandle.move;
    return _CropHandle.none;
  }

  void _onPanStart(DragStartDetails d) {
    _handle = _hitTest(d.localPosition);
    _panStart = d.localPosition;
    _cropAtPanStart = _cropRect;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_handle == _CropHandle.none || _imgRect.isEmpty) return;
    final dx = d.localPosition.dx - _panStart.dx;
    final dy = d.localPosition.dy - _panStart.dy;
    final bottomEdge = _cropAtPanStart.bottom;

    final Rect newCrop;
    switch (_handle) {
      case _CropHandle.none:
        return;
      case _CropHandle.move:
        newCrop = _cropAtPanStart.translate(dx, dy);
      case _CropHandle.br:
        final w = _cropAtPanStart.width + dx;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left, _cropAtPanStart.top, w, w / _idAR);
      case _CropHandle.bl:
        final w = _cropAtPanStart.width - dx;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left + dx, _cropAtPanStart.top, w, w / _idAR);
      case _CropHandle.tr:
        final w = _cropAtPanStart.width + dx;
        final h = w / _idAR;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left, bottomEdge - h, w, h);
      case _CropHandle.tl:
        final w = _cropAtPanStart.width - dx;
        final h = w / _idAR;
        newCrop = Rect.fromLTWH(_cropAtPanStart.left + dx, bottomEdge - h, w, h);
    }

    setState(() => _cropRect = _clampCrop(newCrop, _imgRect));
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _handle = _CropHandle.none);
  }

  // ── Confirm: crop image in isolate, pop with result ──────────────────────

  Future<void> _onConfirm() async {
    if (_naturalSize == null || _imgRect.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);

    final scaleX = _naturalSize!.width / _imgRect.width;
    final scaleY = _naturalSize!.height / _imgRect.height;

    final sx = ((_cropRect.left - _imgRect.left) * scaleX)
        .round()
        .clamp(0, _naturalSize!.width.toInt() - 1);
    final sy = ((_cropRect.top - _imgRect.top) * scaleY)
        .round()
        .clamp(0, _naturalSize!.height.toInt() - 1);
    final sw = (_cropRect.width * scaleX).round();
    final sh = (_cropRect.height * scaleY).round();

    try {
      final result = await compute(
        _doCropImage,
        _CropParams(bytes: widget.imageBytes, srcX: sx, srcY: sy, srcW: sw, srcH: sh),
      );
      if (mounted) Navigator.of(context).pop<Uint8List>(result);
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leadingWidth: 48,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.of(context).pop<Uint8List?>(null),
          tooltip: 'Cancel',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Crop to ID Card',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              'Drag to reposition · handles to resize',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        titleSpacing: 4,
      ),
      body: Column(
        children: [
          // ── Image + crop overlay ─────────────────────────────────────────
          Expanded(
            child: _naturalSize == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : LayoutBuilder(builder: (ctx, cons) {
                    final imgR = _computeImgRect(cons.biggest);
                    if (imgR != _imgRect) {
                      _imgRect = imgR;
                      if (!_cropInitialized && !imgR.isEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _cropRect = _initCropRect(imgR);
                              _cropInitialized = true;
                            });
                          }
                        });
                      }
                    }
                    return GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          if (_cropInitialized)
                            CustomPaint(
                              painter: _CropOverlayPainter(
                                imgRect: _imgRect,
                                cropRect: _cropRect,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
          ),

          // ── Action bar ───────────────────────────────────────────────────
          Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: _isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Processing…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton.icon(
                        onPressed: _cropInitialized ? _onConfirm : null,
                        icon: const Icon(LucideIcons.check, size: 18),
                        label: const Text('Crop & Use'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyazaColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Crop overlay painter ─────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final Rect imgRect;
  final Rect cropRect;

  const _CropOverlayPainter({required this.imgRect, required this.cropRect});

  static const double _armLen = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    // ── 4 dim rects around the crop window ──────────────────────────────────
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, cropRect.top), dim);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom), dim);

    // ── White 2px border ─────────────────────────────────────────────────────
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // ── Rule-of-thirds grid (25 % opacity) ──────────────────────────────────
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width / 3, cropRect.bottom),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.bottom),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height / 3),
      grid,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height * 2 / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height * 2 / 3),
      grid,
    );

    // ── L-shaped corner brackets (3.5 px, round caps) ────────────────────────
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(_armLen, 0), corner);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, _armLen), corner);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(-_armLen, 0), corner);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, _armLen), corner);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(_armLen, 0), corner);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(0, -_armLen), corner);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(-_armLen, 0), corner);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight + const Offset(0, -_armLen), corner);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.cropRect != cropRect || old.imgRect != imgRect;
}
