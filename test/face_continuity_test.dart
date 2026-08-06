import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/face_continuity.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/face_detection.dart';

// ─── Face continuity ──────────────────────────────────────────────────────────
//
// The hole this closes: liveness proved a live human performed the challenges,
// but nothing tied that human to the one being photographed. One person could
// nod and blink while the camera panned to another, and every check passed.
//
// Reported from a real device — "I start with a face and move the camera to
// another face, it never detects that" — for both gesture and flash liveness.

LivenessFaceData _face({
  double x = 0.5,
  double y = 0.5,
  double size = 0.4,
  int? trackingId,
}) =>
    LivenessFaceData(
      headEulerAngleX: 0,
      headEulerAngleY: 0,
      headEulerAngleZ: 0,
      smilingProbability: 0,
      leftEyeOpenProbability: 1,
      rightEyeOpenProbability: 1,
      faceSizeRatio: size,
      faceCenterX: x,
      faceCenterY: y,
      trackingId: trackingId,
    );

final _t0 = DateTime(2026, 1, 1, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  group('the same face', () {
    test('normal head movement is not a substitution', () {
      final guard = FaceContinuityGuard();
      expect(guard.update(_face(), _t0), FaceContinuity.same);
      // Drifting across the frame over several frames, as a real head does.
      for (var i = 1; i <= 6; i++) {
        expect(
          guard.update(_face(x: 0.5 + i * 0.04, y: 0.5), _at(i * 60)),
          FaceContinuity.same,
          reason: 'frame $i is ordinary movement',
        );
      }
    });

    test('leaning in and out is not a substitution', () {
      final guard = FaceContinuityGuard();
      guard.update(_face(size: 0.35), _t0);
      expect(guard.update(_face(size: 0.45), _at(60)), FaceContinuity.same);
      expect(guard.update(_face(size: 0.38), _at(120)), FaceContinuity.same);
    });

    test('a brief dropout — a colour flash hiding the face — is tolerated', () {
      final guard = FaceContinuityGuard();
      guard.update(_face(), _t0);
      guard.reportNoFace();
      expect(guard.update(_face(), _at(400)), FaceContinuity.same,
          reason: 'the flash drops frames; that must not end the session');
    });
  });

  group('a different face', () {
    test('a jump across the frame is a substitution', () {
      final guard = FaceContinuityGuard();
      guard.update(_face(x: 0.25), _t0);
      expect(guard.update(_face(x: 0.75), _at(60)),
          FaceContinuity.substituted);
    });

    test('an abrupt size change is a substitution', () {
      final guard = FaceContinuityGuard();
      guard.update(_face(size: 0.25), _t0);
      expect(guard.update(_face(size: 0.55), _at(60)),
          FaceContinuity.substituted);
    });

    test('a changed tracking id is a substitution even when it looks alike',
        () {
      // Android's ML Kit says outright that this is a different face. Geometry
      // would have missed it — same place, same size.
      final guard = FaceContinuityGuard();
      guard.update(_face(trackingId: 7), _t0);
      expect(guard.update(_face(trackingId: 8), _at(60)),
          FaceContinuity.substituted);
    });

    test('panning to another face is caught by the gap', () {
      // The reported scenario: the camera moves off one person and onto
      // another. The face is absent in between, and nothing vouches for the
      // one that arrives.
      final guard = FaceContinuityGuard();
      guard.update(_face(x: 0.5), _t0);
      guard.reportNoFace();
      expect(guard.update(_face(x: 0.5), _at(1500)),
          FaceContinuity.reacquired);
    });
  });

  group('startup and reset', () {
    test('the first face is the reference, not a substitution', () {
      final guard = FaceContinuityGuard();
      expect(guard.update(_face(x: 0.9, size: 0.7), _t0), FaceContinuity.same);
    });

    test('after a reset the next face becomes the new reference', () {
      final guard = FaceContinuityGuard();
      guard.update(_face(x: 0.2), _t0);
      guard.reset();
      expect(guard.update(_face(x: 0.8), _at(60)), FaceContinuity.same,
          reason: 'a retry starts a fresh session');
    });

    test('iOS reports no tracking id, and the guard still works', () {
      // Apple Vision has no cross-frame identifier, so geometry has to carry
      // the check on that platform.
      final guard = FaceContinuityGuard();
      guard.update(_face(x: 0.25), _t0);
      expect(guard.update(_face(x: 0.8), _at(60)),
          FaceContinuity.substituted);
    });
  });
}
