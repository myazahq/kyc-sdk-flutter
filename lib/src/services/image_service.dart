import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/capture_config.dart';

// ─── Isolate param/result types ───────────────────────────────────────────────
// compute() requires top-level functions, so we pass everything as plain maps.

class _CompressParams {
  final Uint8List bytes;
  final int maxBytes;       // target ceiling in bytes (default 1MB)
  final int startQuality;   // initial JPEG quality (0–100)

  const _CompressParams({
    required this.bytes,
    this.maxBytes = 1024 * 1024,
    this.startQuality = 85,
  });
}

class _CropParams {
  final Uint8List bytes;
  final int x;
  final int y;
  final int width;
  final int height;
  final int maxBytes;

  const _CropParams({
    required this.bytes,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.maxBytes = 1024 * 1024,
  });
}

// ─── Isolate workers (top-level, no closures) ─────────────────────────────────

/// Compresses image bytes to JPEG under [params.maxBytes].
/// Tries [startQuality] first, then steps down by 10 until the size fits
/// or quality reaches 20, at which point it also halves dimensions.
Uint8List _compressWorker(_CompressParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) throw Exception('Could not decode image');

  img.Image source = decoded;
  int quality = params.startQuality;

  while (true) {
    final encoded = img.encodeJpg(source, quality: quality);
    if (encoded.length <= params.maxBytes) return Uint8List.fromList(encoded);

    if (quality > 20) {
      quality -= 10;
    } else {
      // Quality already at floor — halve the dimensions and reset quality
      source = img.copyResize(
        source,
        width: source.width ~/ 2,
        height: source.height ~/ 2,
        interpolation: img.Interpolation.average,
      );
      quality = params.startQuality;
    }
  }
}

/// Crops image bytes to the given bounding box, then compresses to JPEG
/// under [params.maxBytes].
Uint8List _cropAndCompressWorker(_CropParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) throw Exception('Could not decode image');

  final cropped = img.copyCrop(
    decoded,
    x: params.x,
    y: params.y,
    width: params.width,
    height: params.height,
  );

  // Re-use compress logic
  return _compressWorker(_CompressParams(
    bytes: Uint8List.fromList(img.encodeJpg(cropped, quality: 95)),
    maxBytes: params.maxBytes,
  ));
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Compresses [bytes] to a JPEG under 1 MB (or [maxBytes]).
/// Runs in an isolate via [compute] — safe to call from the UI thread.
Future<Uint8List> compressToJpeg(
  Uint8List bytes, {
  int maxBytes = 1024 * 1024,
  int startQuality = 85,
}) {
  return compute(
    _compressWorker,
    _CompressParams(
      bytes: bytes,
      maxBytes: maxBytes,
      startQuality: startQuality,
    ),
  );
}

/// Crops [bytes] to the rectangle defined by [x], [y], [width], [height],
/// then compresses to JPEG under 1 MB (or [maxBytes]).
/// Runs in an isolate via [compute].
Future<Uint8List> cropAndCompress(
  Uint8List bytes, {
  required int x,
  required int y,
  required int width,
  required int height,
  int maxBytes = 1024 * 1024,
}) {
  return compute(
    _cropAndCompressWorker,
    _CropParams(
      bytes: bytes,
      x: x,
      y: y,
      width: width,
      height: height,
      maxBytes: maxBytes,
    ),
  );
}

/// Converts raw image [bytes] to a plain base64 string (no data-URI prefix).
/// Compresses to JPEG under [maxBytes] first — runs in an isolate.
Future<String> toBase64(
  Uint8List bytes, {
  int maxBytes = 1024 * 1024,
  int startQuality = 85,
}) async {
  final compressed = await compressToJpeg(bytes, maxBytes: maxBytes, startQuality: startQuality);
  return base64Encode(compressed);
}

/// Converts raw image [bytes] to a data-URI string suitable for sending
/// directly to the server OCR endpoint: `data:image/jpeg;base64,<data>`.
/// Compresses to JPEG under [maxBytes] first — runs in an isolate.
Future<String> toDataUri(
  Uint8List bytes, {
  int maxBytes = 1024 * 1024,
}) async {
  final b64 = await toBase64(bytes, maxBytes: maxBytes);
  return 'data:image/jpeg;base64,$b64';
}

/// Crops [bytes] to the given bounds, then returns a base64 string.
Future<String> cropToBase64(
  Uint8List bytes, {
  required int x,
  required int y,
  required int width,
  required int height,
  int maxBytes = 1024 * 1024,
}) async {
  final compressed = await cropAndCompress(
    bytes,
    x: x,
    y: y,
    width: width,
    height: height,
    maxBytes: maxBytes,
  );
  return base64Encode(compressed);
}

// ─── Selfie exposure normalisation ──────────────────────────────────────────
//
// Backlit selfies (a bright light/window behind the user) make the camera meter
// for the background, leaving the face in deep shadow. This pass bakes EXIF
// orientation, measures the luminance of the central face region, and — only
// when that region is underexposed — lifts brightness + shadows so the face is
// clearly visible (and matchable). Well-exposed selfies pass through untouched.
// Runs in an isolate via compute().

class _SelfieParams {
  final Uint8List bytes;
  const _SelfieParams(this.bytes);
}

Uint8List _selfieWorker(_SelfieParams p) {
  const maxSide = CaptureConfig.selfieMaxLongEdge;
  const quality = CaptureConfig.selfieImageQuality;

  var im = img.decodeImage(p.bytes);
  if (im == null) return p.bytes;
  im = img.bakeOrientation(im);

  // Downscale only if larger than the cap (never upscale — preserves detail).
  final longEdge = math.max(im.width, im.height);
  if (longEdge > maxSide) {
    final scale = maxSide / longEdge;
    im = img.copyResize(
      im,
      width: (im.width * scale).round(),
      height: (im.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  // Mean luminance (0–255) of the central face region.
  final x0 = (im.width * 0.30).round();
  final x1 = (im.width * 0.70).round();
  final y0 = (im.height * 0.22).round();
  final y1 = (im.height * 0.66).round();
  double total = 0;
  int count = 0;
  for (int y = y0; y < y1; y += 4) {
    for (int x = x0; x < x1; x += 4) {
      total += im.getPixel(x, y).luminance;
      count++;
    }
  }
  final mean = count > 0 ? total / count : 128.0;

  // Lift only when the face region is dark. Gain targets ~135; gamma < 1 pulls
  // up shadows without blowing out midtones.
  if (mean < CaptureConfig.selfieDarkThreshold) {
    final gain = (135.0 / math.max(mean, 18.0)).clamp(1.0, 2.6);
    im = img.adjustColor(im, brightness: gain, gamma: 0.78, contrast: 1.04);
  }

  // Light unsharp-mask to crisp up facial features. `amount` blends the sharpen
  // kernel with the original so it sharpens without harsh halos/noise.
  if (CaptureConfig.selfieSharpenAmount > 0) {
    im = img.convolution(
      im,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
      amount: CaptureConfig.selfieSharpenAmount,
    );
  }

  return Uint8List.fromList(img.encodeJpg(im, quality: quality));
}

/// Bakes orientation, lifts a backlit/underexposed face, and encodes a sharp
/// JPEG for the selfie. Runs in an isolate via [compute].
Future<Uint8List> processSelfieImage(Uint8List bytes) =>
    compute(_selfieWorker, _SelfieParams(bytes));

// ─── Card-region crop ─────────────────────────────────────────────────────────

class _CropCardParams {
  final Uint8List bytes;
  final double viewW;
  final double viewH;
  final int maxBytes;

  const _CropCardParams({
    required this.bytes,
    required this.viewW,
    required this.viewH,
    this.maxBytes = 1024 * 1024,
  });
}

/// Crops the camera frame to the card-guide rectangle that is painted over the
/// viewfinder, then compresses to JPEG under [maxBytes].
///
/// The calculation mirrors [_CardGuidePainter] exactly:
///   • card width  = [viewW] × 0.88
///   • card height = card width / 1.586   (ID-card aspect ratio)
///   • centred horizontally; centred vertically then shifted 20 logical px up
///
/// The BoxFit.cover scale and overflow offsets are applied so the crop
/// coordinates are correct regardless of camera sensor aspect ratio.
/// EXIF orientation is baked before measuring so portrait images are handled
/// correctly on both Android and iOS.
Uint8List _cropCardWorker(_CropCardParams p) {
  var decoded = img.decodeImage(p.bytes);
  if (decoded == null) throw Exception('Could not decode image');

  // Apply EXIF rotation so decoded.width / decoded.height are portrait-correct.
  decoded = img.bakeOrientation(decoded);

  final imgW = decoded.width.toDouble();
  final imgH = decoded.height.toDouble();

  // BoxFit.cover: scale factor (logical px per image px) that makes the image
  // fill the viewfinder without letterboxing.
  final f = math.max(p.viewW / imgW, p.viewH / imgH);

  // How much the scaled image overflows the viewfinder (logical px each side).
  final ox = (imgW * f - p.viewW) / 2;
  final oy = (imgH * f - p.viewH) / 2;

  // Card guide rect in viewfinder logical pixels (mirrors _CardGuidePainter).
  const widthFraction = 0.88;
  const idAspect = 1.586;
  final cardW = p.viewW * widthFraction;
  final cardH = cardW / idAspect;
  final left = (p.viewW - cardW) / 2;
  final top  = (p.viewH - cardH) / 2 - 20.0;

  // Convert to image pixels: logical px → scaled-image px → image px.
  final cropX = ((left + ox) / f).round().clamp(0, decoded.width - 1);
  final cropY = ((top  + oy) / f).round().clamp(0, decoded.height - 1);
  final cropW = (cardW / f).round().clamp(1, decoded.width  - cropX);
  final cropH = (cardH / f).round().clamp(1, decoded.height - cropY);

  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  return _compressWorker(_CompressParams(
    bytes: Uint8List.fromList(img.encodeJpg(cropped, quality: 95)),
    maxBytes: p.maxBytes,
  ));
}

/// Crops [bytes] to the card-guide rectangle as rendered in the document
/// viewfinder of size [viewW] × [viewH] logical pixels, then returns a
/// base64 string. Runs in an isolate via [compute].
Future<String> cropCardRegion(
  Uint8List bytes, {
  required double viewW,
  required double viewH,
  int maxBytes = 1024 * 1024,
}) async {
  final compressed = await cropCardRegionBytes(
    bytes,
    viewW: viewW,
    viewH: viewH,
    maxBytes: maxBytes,
  );
  return base64Encode(compressed);
}

/// Same as [cropCardRegion] but returns the raw compressed JPEG bytes
/// instead of base64. Use this when uploading via multipart so the bytes
/// don't have to be base64-decoded again on the way out.
Future<Uint8List> cropCardRegionBytes(
  Uint8List bytes, {
  required double viewW,
  required double viewH,
  int maxBytes = 1024 * 1024,
}) {
  return compute(
    _cropCardWorker,
    _CropCardParams(bytes: bytes, viewW: viewW, viewH: viewH, maxBytes: maxBytes),
  );
}

/// Returns the size in bytes of a base64-encoded image (no data-URI prefix).
int base64SizeBytes(String base64Str) {
  // Each base64 char encodes 6 bits; 4 chars = 3 bytes.
  // Subtract padding characters.
  final padding = base64Str.endsWith('==')
      ? 2
      : base64Str.endsWith('=')
          ? 1
          : 0;
  return (base64Str.length * 3 ~/ 4) - padding;
}

/// Strips a data-URI prefix (e.g. `data:image/jpeg;base64,`) if present.
String stripDataUri(String input) {
  final idx = input.indexOf(',');
  return idx == -1 ? input : input.substring(idx + 1);
}
