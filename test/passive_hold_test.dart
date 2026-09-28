import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/face_detection.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/passive_hold.dart';

// Passive Liveness passes on its own after about two seconds of a steady,
// centred face, and the two seconds must be CONSECUTIVE.

final _t0 = DateTime(2026, 9, 27, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

LivenessFaceData _face({double yaw = 0, double? x = 0.5, double? y = 0.5}) =>
    LivenessFaceData(
      headEulerAngleX: 0,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      smilingProbability: 0,
      leftEyeOpenProbability: 1,
      rightEyeOpenProbability: 1,
      faceSizeRatio: 0.4,
      faceCenterX: x,
      faceCenterY: y,
    );

/// Frames every [stepMs] from [fromMs] to [toMs], all in position.
bool _feed(PassiveHold hold, int fromMs, int toMs, {int stepMs = 100}) {
  var passed = false;
  for (var ms = fromMs; ms <= toMs; ms += stepMs) {
    passed = hold.update(inPosition: true, now: _at(ms));
  }
  return passed;
}

void main() {
  test('passes after about two seconds in position, not before', () {
    final hold = PassiveHold();
    expect(_feed(hold, 0, 1900), isFalse);
    expect(hold.update(inPosition: true, now: _at(2000)), isTrue);
  });

  test('leaving position starts the hold over', () {
    final hold = PassiveHold();
    _feed(hold, 0, 1500);
    expect(hold.update(inPosition: false, now: _at(1600)), isFalse);
    expect(_feed(hold, 1700, 3600), isFalse);
    expect(hold.update(inPosition: true, now: _at(3700)), isTrue);
  });

  test('a long silence between frames starts the hold over', () {
    final hold = PassiveHold();
    _feed(hold, 0, 1500);
    expect(hold.update(inPosition: true, now: _at(2500)), isFalse);
    expect(_feed(hold, 2600, 4400), isFalse);
    expect(hold.update(inPosition: true, now: _at(4500)), isTrue);
  });

  test('reset starts the hold over', () {
    final hold = PassiveHold();
    _feed(hold, 0, 1900);
    hold.reset();
    expect(hold.update(inPosition: true, now: _at(2000)), isFalse);
  });

  test('works at a slow frame rate too', () {
    final hold = PassiveHold();
    expect(_feed(hold, 0, 2000, stepMs: 400), isTrue);
  });

  group('a frame in position', () {
    test('a centred face looking at the camera counts', () {
      expect(holdFrameInPosition(_face()), isTrue);
    });

    test('a turned head does not', () {
      expect(holdFrameInPosition(_face(yaw: 35)), isFalse);
    });

    test('a face far off centre does not', () {
      expect(holdFrameInPosition(_face(x: 0.9)), isFalse);
      expect(holdFrameInPosition(_face(y: 0.1)), isFalse);
    });

    test('an unreported centre does not block the hold', () {
      expect(holdFrameInPosition(_face(x: null, y: null)), isTrue);
    });
  });
}
