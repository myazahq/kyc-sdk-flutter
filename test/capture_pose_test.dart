import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/capture_pose.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/face_detection.dart';

LivenessFaceData face({double yaw = 0, double pitch = 0, double roll = 0}) =>
    LivenessFaceData(
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: roll,
      smilingProbability: 0,
      leftEyeOpenProbability: 1,
      rightEyeOpenProbability: 1,
      faceSizeRatio: 0.4,
    );

/// Feeds frames 100 ms apart; true when any of them ended the wait.
bool settles(List<LivenessFaceData> frames) {
  final watch = StraightWatch();
  var at = DateTime(2026);
  var done = false;
  for (final frame in frames) {
    done = watch.update(frame, at);
    at = at.add(const Duration(milliseconds: 100));
  }
  return done;
}

void main() {
  test('a face at rest, facing the camera, is photographed after the hold', () {
    expect(settles(List.filled(6, face())), isTrue);
    // Not on the first frames: there is nothing yet to call rest.
    expect(settles(List.filled(2, face())), isFalse);
  });

  test('a face still coming back from a turn is not', () {
    expect(settles([for (var yaw = 30.0; yaw > 12; yaw -= 3) face(yaw: yaw)]),
        isFalse);
    // Held off to one side, however still.
    expect(settles(List.filled(8, face(yaw: 18))), isFalse);
  });

  test('a nod in motion is not, and one that has stopped is', () {
    expect(
      settles([for (var pitch = -30.0; pitch < 0; pitch += 6) face(pitch: pitch)]),
      isFalse,
    );
    expect(
      settles([
        for (var pitch = -30.0; pitch < 0; pitch += 6) face(pitch: pitch),
        ...List.filled(6, face()),
      ]),
      isTrue,
    );
  });

  test('pitch and roll with no true zero do not block the photo', () {
    // An iPhone that reports a steady offset on both: at rest all the same.
    expect(settles(List.filled(6, face(pitch: -22, roll: 95))), isTrue);
  });

  test('moving again restarts the hold', () {
    expect(
      settles([
        ...List.filled(3, face()),
        face(yaw: 9),
        ...List.filled(2, face(yaw: 9)),
      ]),
      isFalse,
    );
  });

  test('straight is well inside what a turn gesture asks for', () {
    expect(kStraightYaw, lessThan(25 / 2));
  });
}
