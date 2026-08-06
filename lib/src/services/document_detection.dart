import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

// ─── Document detection (auto-capture) ────────────────────────────────────────
//
// Bridge to the native document-edge detector. iOS uses Apple Vision; there is
// no ML Kit equivalent on Android, so `detect` simply returns null there and
// the screen keeps its manual shutter. Auto-capture is an accelerator, never
// the only way to take the photo.
//
// The native side reports WHERE the document is; the decision to fire lives
// here (see [DocumentFramingGate]) so thresholds are tunable without a native
// rebuild.

/// A detected document's normalized bounding box (0..1, top-left origin).
class DocumentBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;

  /// True width/height ratio in ORIENTED pixels — not the normalized w/h, which
  /// is skewed by the frame's own aspect. This is what tells an ID card apart
  /// from a book or a receipt.
  final double aspectRatio;

  const DocumentBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.aspectRatio,
  });

  double get area => width * height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  /// How far the box's centre sits from the frame's centre, 0 = centred.
  double get offCentre =>
      ((centerX - 0.5).abs() + (centerY - 0.5).abs()) / 2;

  /// Smallest gap between any edge of the document and the frame edge. Negative
  /// is impossible (the box is clamped), 0 means an edge is touching — which
  /// usually means a corner is already cut off.
  double get edgeMargin {
    final left = x;
    final top = y;
    final right = 1 - (x + width);
    final bottom = 1 - (y + height);
    return [left, top, right, bottom].reduce((a, b) => a < b ? a : b);
  }

  static DocumentBox? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final w = (map['width'] as num?)?.toDouble();
    final h = (map['height'] as num?)?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return DocumentBox(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      width: w,
      height: h,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? (w / h),
    );
  }
}

/// One frame's worth of detection: the document if found, plus the frame's
/// overall brightness. Brightness is reported even when nothing was detected —
/// a dark frame is the most common reason for finding nothing, and telling the
/// user to add light is more useful than "keep trying".
class DocumentDetection {
  final DocumentBox? box;

  /// Mean luma of the frame, 0..1.
  final double brightness;

  const DocumentDetection({required this.box, required this.brightness});
}

class DocumentDetectionService {
  static const MethodChannel _channel =
      MethodChannel('kyc_sdk_flutter/document_detection');

  bool _busy = false;
  bool _unsupported = false;

  /// True while a frame is in flight — callers drop frames rather than queue
  /// them, since detection is slower than the camera.
  bool get isBusy => _busy;

  /// True once the platform has shown it has no detector, so the caller can
  /// stop sending frames and leave the manual shutter in place.
  bool get isUnsupported => _unsupported;

  Future<DocumentDetection?> detect(CameraImage image) async {
    if (_unsupported || _busy) return null;
    if (!Platform.isIOS && !Platform.isAndroid) {
      _unsupported = true;
      return null;
    }
    if (image.planes.isEmpty) return null;

    _busy = true;
    try {
      final planes = image.planes
          .map((p) => <String, dynamic>{
                'bytes': p.bytes,
                'bytesPerRow': p.bytesPerRow,
                'bytesPerPixel': p.bytesPerPixel,
              })
          .toList(growable: false);

      final result = await _channel.invokeMapMethod<String, dynamic>('detect', {
        'width': image.width,
        'height': image.height,
        'planes': planes,
      });
      if (result == null) return null;
      return DocumentDetection(
        box: DocumentBox.fromMap(result),
        // Mid-grey when the platform didn't report one, so a missing value
        // never triggers a spurious "add light".
        brightness: (result['brightness'] as num?)?.toDouble() ?? 0.5,
      );
    } on MissingPluginException {
      _unsupported = true; // Android — no detector shipped.
      return null;
    } on PlatformException {
      return null;
    } finally {
      _busy = false;
    }
  }
}
