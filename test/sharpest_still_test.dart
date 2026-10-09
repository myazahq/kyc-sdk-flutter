import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/sharpest_still.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/selfie_sharpness.dart';

ScoredStill still(int id, double? score) =>
    ScoredStill(Uint8List.fromList([id]), score);

void main() {
  test('the highest score wins, wherever it sits in the burst', () {
    final best = sharpestOf([still(1, 12), still(2, 40), still(3, 25)]);
    expect(best!.bytes.single, 2);
  });

  test('a measured photo beats one that could not be measured', () {
    expect(sharpestOf([still(1, null), still(2, 5)])!.bytes.single, 2);
    expect(sharpestOf([still(1, 5), still(2, null)])!.bytes.single, 1);
  });

  test('with nothing measured, the most recent is kept', () {
    expect(sharpestOf([still(1, null), still(2, null)])!.bytes.single, 2);
  });

  test('no photos, no answer', () {
    expect(sharpestOf(const []), isNull);
  });

  test('soft is below the floor, and unmeasured is never soft', () {
    expect(still(1, kSelfieSharpnessFloor - 1).soft, isTrue);
    expect(still(1, kSelfieSharpnessFloor).soft, isFalse);
    expect(still(1, null).soft, isFalse);
  });

  test('the retakes are bounded, so a smudged lens cannot loop', () {
    expect(kSoftRetakes, lessThanOrEqualTo(2));
  });
}
