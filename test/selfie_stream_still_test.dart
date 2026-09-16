import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myaza_kyc_sdk_flutter/src/config/capture_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/image_service.dart';

// ─── The Android liveness still keeps the preview's exposure ─────────────────
//
// Android takes the selfie from the latest analysis frame (the native
// recorder's captureStillJpeg), which is already exposed the way the preview
// looked. It used to run through processSelfieImage, whose dark-face lift reads
// a face-region mean under 115 as backlit, so an ordinary indoor face came back
// visibly brighter than the screen it was taken from (Galaxy S24, 2026-09-15).

/// A JPEG the size of a front-camera frame, lit like an indoor face.
Uint8List _indoorFrame({int width = 720, int height = 960}) {
  final im = img.Image(width: width, height: height);
  img.fill(im, color: img.ColorRgb8(90, 90, 90));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Mean luminance over the region the lift measures.
double _faceRegionMean(Uint8List jpeg) {
  final im = img.decodeJpg(jpeg)!;
  var total = 0.0;
  var count = 0;
  for (var y = (im.height * 0.22).round(); y < (im.height * 0.66).round(); y += 4) {
    for (var x = (im.width * 0.30).round(); x < (im.width * 0.70).round(); x += 4) {
      total += im.getPixel(x, y).luminance;
      count++;
    }
  }
  return total / count;
}

void main() {
  test('the stream still keeps the exposure it was captured with', () async {
    final frame = _indoorFrame();
    final out = await processSelfieStreamStill(frame);
    expect(_faceRegionMean(out), closeTo(_faceRegionMean(frame), 4));
  });

  test('a takePicture still of the same scene is still lifted', () async {
    // The lift stays where it belongs: a real still can be metered for a bright
    // background, and that path must keep brightening a dark face.
    final frame = _indoorFrame();
    final out = await processSelfieImage(frame);
    expect(_faceRegionMean(out), greaterThan(_faceRegionMean(frame) + 20));
  });

  test('the stream still is still size-bounded', () async {
    final out = await processSelfieStreamStill(_indoorFrame(width: 2160, height: 2880));
    final decoded = img.decodeJpg(out)!;
    expect(
      math.max(decoded.width, decoded.height),
      lessThanOrEqualTo(CaptureConfig.selfieMaxLongEdge),
    );
    expect(out.length, lessThanOrEqualTo(CaptureConfig.selfieMaxBytes));
  });

  test('the Android native still takes the lean encode', () {
    // The defect was the choice of encoder at one call site, which no
    // behavioural test of the encoders can see.
    final source = File('lib/src/screens/liveness_screen.dart').readAsStringSync();
    expect(source, contains('processSelfieStreamStill(selfie)'));
    expect(source, isNot(contains('processSelfieImage(selfie)')));
  });
}
