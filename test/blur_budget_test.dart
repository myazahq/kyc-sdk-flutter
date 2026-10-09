import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/blur_budget.dart';

// The full-screen liveness camera gives its blur up on a phone that cannot
// draw it in time (liveness/blur_budget.dart).

const _fast = Duration(milliseconds: 8);
const _slow = Duration(milliseconds: 30);

void _feed(BlurBudget budget, Duration frame, int count) {
  for (var i = 0; i < count; i++) {
    budget.add(frame);
  }
}

void main() {
  test('a phone that keeps up keeps the blur', () {
    final budget = BlurBudget();
    _feed(budget, _fast, 600);
    expect(budget.affordable, isTrue);
  });

  test('the first frames after the camera opens are not judged', () {
    final budget = BlurBudget();
    _feed(budget, _slow, kBlurWarmupFrames);
    _feed(budget, _fast, kBlurWindowFrames * 3);
    expect(budget.affordable, isTrue);
  });

  test('a window of mostly slow frames ends the blur, once', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    var ended = 0;
    for (var i = 0; i < kBlurWindowFrames; i++) {
      if (budget.add(_slow)) ended++;
    }
    expect(budget.affordable, isFalse);
    expect(ended, 1);
  });

  test('a few slow frames in a window are tolerated', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    for (var i = 0; i < kBlurWindowFrames * 4; i++) {
      // One in four is slow: under the share that ends the blur.
      budget.add(i % 4 == 0 ? _slow : _fast);
    }
    expect(budget.affordable, isTrue);
  });

  test('the blur never comes back', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    _feed(budget, _slow, kBlurWindowFrames);
    _feed(budget, _fast, kBlurWindowFrames * 10);
    expect(budget.affordable, isFalse);
  });
}
