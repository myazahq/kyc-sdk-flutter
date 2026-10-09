import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_detector.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_liveness_runner.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/flash_timeline.dart';

void main() {
  group('flash colour times', () {
    test('are measured from the start of the recording', () {
      expect(flashOnsets([5450, 6550, 7650], 3, startedAt: 1000), [4450, 5550, 6650]);
    });

    test('are left out when nothing was recording', () {
      expect(flashOnsets([5450, 6550], 2, useMarked: false), isNull);
    });

    test('are left out when a colour never ran, came on early, or they do not rise', () {
      expect(flashOnsets([5450, 6550], 3, startedAt: 1000), isNull);
      expect(flashOnsets([900, 2000], 2, startedAt: 1000), isNull);
      expect(flashOnsets([5450, 5450], 2, startedAt: 1000), isNull);
    });

    test('ride on the flash result and its wire form, one per colour', () async {
      var clock = 10000;
      Color? shown;
      final sequence = generateFlashSequence(3);
      final runner = FlashSequenceRunner(
        paint: (color) {
          shown = color;
          clock += 550; // each paint is half a beat on
        },
        sampleFace: (_) async => shown == null ? [100.0, 100.0, 100.0] : [130.0, 130.0, 130.0],
        timings: FlashTimings.instant,
        now: () => clock,
        recordingStartedAt: () => 9000,
      );
      final result = await runner.run(sequence);
      expect(result.onsets, hasLength(3));
      expect(result.onsets![0], greaterThan(1000));
      expect(result.onsets![1], greaterThan(result.onsets![0]));
      expect(result.toJson()['onsets'], result.onsets);
    });

    test('are absent from the wire form when there was no recording', () async {
      final runner = FlashSequenceRunner(
        paint: (_) {},
        sampleFace: (_) async => [100.0, 100.0, 100.0],
        timings: FlashTimings.instant,
        recordingStartedAt: () => null,
      );
      final result = await runner.run(generateFlashSequence(2));
      expect(result.onsets, isNull);
      expect(result.toJson().containsKey('onsets'), isFalse);
    });
  });
}
