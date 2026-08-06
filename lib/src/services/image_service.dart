import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../config/document_guide.dart';
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
  var im = img.decodeImage(p.bytes);
  if (im == null) return p.bytes;
  im = img.bakeOrientation(im);
  return _enhanceAndEncodeSelfie(im);
}

// ── Stream-frame selfie path (no takePicture mode-switch) ────────────────────
//
// Encodes the selfie directly from a live camera-stream frame we already have
// during "hold still", avoiding the slow video→photo capture-session switch
// (`stopVideoRecording()` + `takePicture()`), which added several seconds on iOS.

class _SelfieFrameParams {
  final Uint8List bytes;   // raw frame plane bytes
  final int width;
  final int height;
  final int bytesPerRow;   // row stride of the source plane
  final bool bgra;         // true = iOS BGRA8888; false = treat as already-RGB(A)
  final bool mirror;       // front camera → mirror horizontally
  const _SelfieFrameParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bgra,
    required this.mirror,
  });
}

Uint8List _selfieFrameWorker(_SelfieFrameParams p) {
  // CameraImage plane bytes are frequently a *view* into a larger ByteBuffer
  // (non-zero offsetInBytes). Passing `.buffer` directly would start decoding at
  // the wrong place and misalign the BGRA channels (purple/green cast). Copy to a
  // fresh, zero-offset buffer of exactly the plane length first.
  final clean = Uint8List.fromList(p.bytes);
  var im = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: clean.buffer,
    rowStride: p.bytesPerRow,
    order: p.bgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
    numChannels: 4,
  );
  // Front camera: mirror to match what the user saw in the preview.
  if (p.mirror) im = img.flipHorizontal(im);
  // Stream frames are already at preview exposure — run the LEAN encode (resize +
  // encode only). The heavy dark-face lift is tuned for stills and blows preview
  // frames out, so it is skipped here.
  return _resizeAndEncodeSelfie(im);
}

/// Encodes a selfie [from a stream frame]: BGRA bytes → enhanced JPEG. Runs in an
/// isolate via [compute]. Returns null on failure so the caller can fall back.
Future<Uint8List?> processSelfieFrame({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required bool bgra,
  required bool mirror,
}) async {
  try {
    return await compute(
      _selfieFrameWorker,
      _SelfieFrameParams(
        bytes: bytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        bgra: bgra,
        mirror: mirror,
      ),
    );
  } catch (_) {
    return null;
  }
}

// Downscale to the selfie cap (never upscale — preserves detail).
img.Image _downscaleSelfie(img.Image im) {
  const maxSide = CaptureConfig.selfieMaxLongEdge;
  final longEdge = math.max(im.width, im.height);
  if (longEdge <= maxSide) return im;
  final scale = maxSide / longEdge;
  return img.copyResize(
    im,
    width: (im.width * scale).round(),
    height: (im.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

// Encodes a selfie JPEG under [CaptureConfig.selfieMaxBytes]. Steps quality down
// from [selfieImageQuality] to [selfieMinQuality] first (preserving resolution =
// facial detail); only if still too large does it scale dimensions down. Keeps
// the file small enough to upload while sharp enough for facial comparison.
Uint8List _encodeSelfieUnderBudget(img.Image image) {
  const maxBytes = CaptureConfig.selfieMaxBytes;
  const minQuality = CaptureConfig.selfieMinQuality;

  var im = image;
  var quality = CaptureConfig.selfieImageQuality;
  while (true) {
    final encoded = img.encodeJpg(im, quality: quality);
    if (encoded.length <= maxBytes || (quality <= minQuality && im.width <= 480)) {
      return Uint8List.fromList(encoded);
    }
    if (quality > minQuality) {
      quality -= 6;
    } else {
      // Quality floor reached and still over budget — shrink and retry from top.
      im = img.copyResize(
        im,
        width: (im.width * 0.85).round(),
        height: (im.height * 0.85).round(),
        interpolation: img.Interpolation.average,
      );
      quality = CaptureConfig.selfieImageQuality;
    }
  }
}

// Lean encode: resize + size-bounded JPEG only, no exposure lift. Used for stream
// frames, which are already at preview exposure (the heavy lift blows them out).
Uint8List _resizeAndEncodeSelfie(img.Image input) =>
    _encodeSelfieUnderBudget(_downscaleSelfie(input));

// Shared selfie enhancement + encode (used by the still-capture path).
Uint8List _enhanceAndEncodeSelfie(img.Image input) {
  var im = _downscaleSelfie(input);

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

  return _encodeSelfieUnderBudget(im);
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
  final double aspect;
  final int maxBytes;

  const _CropCardParams({
    required this.bytes,
    required this.viewW,
    required this.viewH,
    this.aspect = 1.586,
    this.maxBytes = 1024 * 1024,
  });
}

/// Crops the camera frame to the card-guide rectangle that is painted over the
/// viewfinder, then compresses to JPEG under [maxBytes].
///
/// The calculation mirrors [_CardGuidePainter] exactly:
///   • card width  = [viewW] × 0.88
///   • card height = card width / aspect  (1.586 for ID cards; a taller ratio
///     for passports so the data page's bottom MRZ band is included)
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

  // Guide rect in viewfinder logical pixels — from the SAME function the
  // on-screen overlay paints, so the crop can never take a different rectangle
  // than the one the user framed against.
  final guide = documentGuideRect(ui.Size(p.viewW, p.viewH), p.aspect);
  final cardW = guide.width;
  final cardH = guide.height;
  final left = guide.left;
  final top = guide.top;

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
  double aspect = 1.586,
  int maxBytes = 1024 * 1024,
}) async {
  final compressed = await cropCardRegionBytes(
    bytes,
    viewW: viewW,
    viewH: viewH,
    aspect: aspect,
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
  double aspect = 1.586,
  int maxBytes = 1024 * 1024,
}) {
  return compute(
    _cropCardWorker,
    _CropCardParams(
      bytes: bytes,
      viewW: viewW,
      viewH: viewH,
      aspect: aspect,
      maxBytes: maxBytes,
    ),
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

// ─── MRZ band ─────────────────────────────────────────────────────────────────
//
// The machine-readable zone lives in the bottom band of a passport data page.
// Handing a general text recogniser the WHOLE page makes it compete with the
// printed fields, the portrait and the background pattern; handing it just the
// band, enlarged, is the single biggest thing that makes OCR-B read reliably.
// The same reasoning as the server's local MRZ scanner, which crops the lower
// portion and upscales before recognition.

class _MrzBandParams {
  final Uint8List bytes;
  final double bandFraction;
  final int minWidth;
  const _MrzBandParams(this.bytes, this.bandFraction, this.minWidth);
}

Uint8List? _mrzBandWorker(_MrzBandParams p) {
  final img.Image? decoded;
  try {
    // Throws rather than returning null on bytes it cannot make sense of. The
    // band is one extra candidate, never a requirement, so a failure here must
    // leave the full-frame attempts to run.
    decoded = img.decodeImage(p.bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  final bandHeight = (decoded.height * p.bandFraction).round();
  if (bandHeight <= 0) return null;
  var band = img.copyCrop(
    decoded,
    x: 0,
    y: decoded.height - bandHeight,
    width: decoded.width,
    height: bandHeight,
  );

  // Upscale a small band: OCR-B at low pixel height is where recognisers give
  // up, and the cost of resampling is trivial next to a failed read.
  if (band.width < p.minWidth) {
    final scale = p.minWidth / band.width;
    band = img.copyResize(
      band,
      width: p.minWidth,
      height: (band.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  return Uint8List.fromList(img.encodeJpg(band, quality: 92));
}

/// The bottom [bandFraction] of an image, upscaled to at least [minWidth] —
/// the strip a passport's machine-readable zone occupies. Returns null when the
/// image cannot be decoded; callers treat that as "no extra candidate".
Future<Uint8List?> cropMrzBand(
  Uint8List bytes, {
  double bandFraction = 0.42,
  int minWidth = 1600,
}) =>
    compute(_mrzBandWorker, _MrzBandParams(bytes, bandFraction, minWidth));
