import 'dart:async';

import 'package:camera/camera.dart';

// ─── Face-region RGB sampling ─────────────────────────────────────────────────
//
// The camera-facing half of flash liveness: the mean RGB of the face region for
// one frame, which `FlashSequenceRunner` correlates against the color the screen
// painted.
//
// The region is a CENTER 40% × 50% CROP, not a detected face box. That is not an
// approximation — it is the contract. The web SDK samples the same crop
// (liveness/flash-detector.ts) and the server re-scores the recorded video with
// the same crop (src/docbio/ffmpeg.ts). All three must agree, or the server's
// independent check of the client's claim compares different pixels and reports
// a mismatch for an honest capture. Change one, change all three.
//
// It is also sound on its own terms: the liveness step already requires a
// centered face filling the oval, so the crop IS the face.

/// Mean `[r, g, b]` (0–255) of the frame's center crop, or null if the frame
/// can't be read. Never throws — a bad frame is a missing sample, and a missing
/// sample is scored inconclusive (fails soft) rather than failed.
List<double>? sampleFrameRgb(CameraImage image) {
  try {
    if (image.planes.isEmpty) return null;
    return image.planes.length >= 3
        ? _sampleYuv420(image)
        : _sampleBgra(image);
  } catch (_) {
    return null;
  }
}

/// The crop bounds + step, sized to visit roughly a 32×32 grid — the same
/// resolution the web downscales to, so both average comparable detail.
({int x0, int x1, int y0, int y1, int sx, int sy}) _cropGrid(int w, int h) {
  final cropW = (w * 0.4).round();
  final cropH = (h * 0.5).round();
  final x0 = ((w - cropW) / 2).round();
  final y0 = ((h - cropH) / 2).round();
  return (
    x0: x0,
    x1: x0 + cropW,
    y0: y0,
    y1: y0 + cropH,
    sx: (cropW ~/ 32).clamp(1, 999),
    sy: (cropH ~/ 32).clamp(1, 999),
  );
}

/// iOS: BGRA8888 — interleaved B, G, R, A.
List<double>? _sampleBgra(CameraImage image) {
  final plane = image.planes[0];
  final bytes = plane.bytes;
  final bpr = plane.bytesPerRow;
  final bpp = (bpr ~/ image.width).clamp(1, 8);
  final g = _cropGrid(image.width, image.height);

  double r = 0, gr = 0, b = 0;
  int count = 0;
  for (int y = g.y0; y < g.y1; y += g.sy) {
    final row = y * bpr;
    for (int x = g.x0; x < g.x1; x += g.sx) {
      final i = row + x * bpp;
      if (i + 2 >= bytes.length) continue;
      b += bytes[i];
      gr += bytes[i + 1];
      r += bytes[i + 2];
      count++;
    }
  }
  if (count == 0) return null;
  return [r / count, gr / count, b / count];
}

/// Android: YUV420 — Y full-res in plane 0, U/V subsampled in planes 1/2.
/// Converted per sampled pixel (BT.601); only ~1k pixels are touched per frame,
/// so a full-frame conversion would be wasted work.
List<double>? _sampleYuv420(CameraImage image) {
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final g = _cropGrid(image.width, image.height);

  double r = 0, gr = 0, b = 0;
  int count = 0;
  for (int y = g.y0; y < g.y1; y += g.sy) {
    final yRow = y * yPlane.bytesPerRow;
    final uvRow = (y >> 1) * uvRowStride;
    for (int x = g.x0; x < g.x1; x += g.sx) {
      final yi = yRow + x;
      final uvi = uvRow + (x >> 1) * uvPixelStride;
      if (yi >= yPlane.bytes.length ||
          uvi >= uPlane.bytes.length ||
          uvi >= vPlane.bytes.length) {
        continue;
      }
      final yv = yPlane.bytes[yi].toDouble();
      final u = uPlane.bytes[uvi] - 128.0;
      final v = vPlane.bytes[uvi] - 128.0;
      r += (yv + 1.370705 * v).clamp(0.0, 255.0);
      gr += (yv - 0.337633 * u - 0.698001 * v).clamp(0.0, 255.0);
      b += (yv + 1.732446 * u).clamp(0.0, 255.0);
      count++;
    }
  }
  if (count == 0) return null;
  return [r / count, gr / count, b / count];
}

/// Averages every frame that arrives over [window] into one sample.
///
/// A single frame is too noisy to correlate: sensor noise and auto-exposure
/// drift are the same order as a real flash's reflection. The web averages ~15
/// samples/sec across the window for the same reason; this averages whatever
/// the stream delivers, which is equivalent and avoids polling a frame that
/// hasn't changed.
///
/// [latest] returns the most recent frame, or null when none has arrived.
class WindowedRgbSampler {
  /// The latest face-region `[r,g,b]` (0–255), or null when unavailable. On iOS
  /// this samples the cached CameraImage; on Android it returns the RGB the
  /// native recorder ships per frame — the caller supplies the right source, so
  /// this class is platform-agnostic.
  final List<double>? Function() latestRgb;

  const WindowedRgbSampler(this.latestRgb);

  Future<List<double>?> sample(Duration window) async {
    final samples = <List<double>>[];
    final deadline = DateTime.now().add(window);

    while (DateTime.now().isBefore(deadline)) {
      final rgb = latestRgb();
      if (rgb != null && rgb.length == 3) samples.add(rgb);
      await Future<void>.delayed(const Duration(milliseconds: 33));
    }

    if (samples.isEmpty) return null;
    double r = 0, g = 0, b = 0;
    for (final s in samples) {
      r += s[0];
      g += s[1];
      b += s[2];
    }
    final n = samples.length;
    return [r / n, g / n, b / n];
  }
}
