// ─── Was the selfie sharp enough? Measured the moment it is taken ────────────
//
// The Flutter mirror of the web SDK's lib/selfie-sharpness.ts and the React
// Native SDK's lib/selfie-sharpness.ts. Keep the three in lockstep: the floor,
// the crop fraction and the measuring size are what make a score mean the same
// thing on every platform.
//
// The server can already say a failed face check was caused by a blurry
// selfie, but that reaches the applicant by webhook long after the phone is
// back in a pocket. The review screen is the one place a retake costs two
// seconds, so the same question is asked here.
//
// A NOTICE, NEVER A GATE. The floor was not calibrated on real phone captures,
// and a wrong floor on a gate would trap a genuine applicant in a retake loop.
// As a notice the cost of a wrong floor is one sentence the applicant can
// ignore: Continue stays available whatever this says.
//
// MEASURED ON THE FACE, NOT THE FRAME. The capture gate only fires once the
// face is centred and fills a good part of the frame, so the centre of the
// still IS the face. A centred square is unchanged by a 90 degree rotation or a
// mirror, so orientation cannot move the measurement onto the room.
//
// The decode is pure Dart, so it runs in an isolate via compute().

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Below this, the notice shows. A starting value, biased toward NOT showing.
const double kSelfieSharpnessFloor = 18;

/// Share of the shorter side the centre crop takes.
const double kSelfieCropFraction = 0.5;

/// The crop is resized to a FIXED size before measuring, because Laplacian
/// variance scales with resolution: without it the score would measure the
/// phone's camera rather than the photograph.
const int kSelfieMeasureSize = 160;

/// Variance of the 4-neighbour Laplacian over a single-channel plane.
///
/// Blur is a low-pass filter, so it flattens second derivatives, so the spread
/// of the Laplacian response collapses. The same measure the server runs.
double laplacianVariance(List<int> gray, int width, int height) {
  if (width < 3 || height < 3 || gray.length < width * height) return 0;
  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < height - 1; y++) {
    final row = y * width;
    for (var x = 1; x < width - 1; x++) {
      final i = row + x;
      final v = gray[i - width] + gray[i + width] + gray[i - 1] + gray[i + 1] - 4 * gray[i];
      sum += v;
      sumSq += v * v;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return ((sumSq / n - mean * mean) * 100).round() / 100;
}

/// A centred square covering [fraction] of the shorter side.
({int x, int y, int side}) selfieCentreCrop(
  int width,
  int height, [
  double fraction = kSelfieCropFraction,
]) {
  final shorter = width < height ? width : height;
  final side = (shorter * fraction).round().clamp(1, shorter < 1 ? 1 : shorter);
  return (
    x: ((width - side) / 2).round().clamp(0, width),
    y: ((height - side) / 2).round().clamp(0, height),
    side: side,
  );
}

/// Whether to show the notice. An unmeasurable selfie is NOT blurry: "we could
/// not look" is not evidence the photograph was soft.
bool isSelfieBlurry(double? score) =>
    score != null && score < kSelfieSharpnessFloor;

/// Decode a still and measure its centre. Null on any failure.
///
/// Top-level so compute() can send it to an isolate.
double? measureSelfieSharpnessBytes(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width < 3 || decoded.height < 3) return null;
    final c = selfieCentreCrop(decoded.width, decoded.height);
    final face = img.copyCrop(decoded, x: c.x, y: c.y, width: c.side, height: c.side);
    final small = img.copyResize(
      face,
      width: kSelfieMeasureSize,
      height: kSelfieMeasureSize,
      interpolation: img.Interpolation.linear,
    );
    // Channel values are in the image's own range (255 for a JPEG).
    final scale = 255 / small.maxChannelValue;
    final gray = Uint8List(small.width * small.height);
    for (var y = 0; y < small.height; y++) {
      for (var x = 0; x < small.width; x++) {
        final p = small.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * scale;
        gray[y * small.width + x] = lum.round().clamp(0, 255);
      }
    }
    return laplacianVariance(gray, small.width, small.height);
  } catch (_) {
    return null;
  }
}

/// Measure a base64 JPEG off the UI thread. Null on any failure.
Future<double?> measureSelfieSharpness(String base64Jpeg) async {
  try {
    final bytes = base64Decode(base64Jpeg);
    return await compute(measureSelfieSharpnessBytes, bytes);
  } catch (_) {
    return null;
  }
}
