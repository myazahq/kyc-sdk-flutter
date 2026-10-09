import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/face_window.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/liveness_cutout.dart';

void main() {
  // An iPhone 16 Pro Max showing a 9:16 frame cover-fit, with the full-screen
  // window (280 by 370) at its centre.
  final window = faceWindowFor(
    screen: const Size(440, 956),
    window: const Size(280, 369.6),
    frameAspect: 9 / 16,
  );

  test('the window is a share of the frame as it is drawn', () {
    // The frame is drawn 956 high, so 537.75 wide; the screen crops its sides.
    expect(window.width, closeTo(280 / 537.75, 0.001));
    expect(window.height, closeTo(369.6 / 956, 0.001));
  });

  test('a wider screen than the frame fits the frame to its width', () {
    final wide = faceWindowFor(
      screen: const Size(800, 1000),
      window: const Size(280, 370),
      frameAspect: 9 / 16,
    );
    expect(wide.width, closeTo(280 / 800, 0.001));
  });

  test('a face that sits in the window needs nothing', () {
    expect(
      faceWindowGuidance(window,
          faceWidth: window.width * 0.65, centreX: 0.5, centreY: 0.5),
      isNull,
    );
  });

  test('a face spilling over the window is too close', () {
    expect(
      faceWindowGuidance(window, faceWidth: window.width, centreX: 0.5, centreY: 0.5),
      'too_close',
    );
  });

  test('a small face is too far', () {
    expect(
      faceWindowGuidance(window,
          faceWidth: window.width * 0.3, centreX: 0.5, centreY: 0.5),
      'too_far',
    );
  });

  test('a face beside the window is off centre, on either axis', () {
    final fill = window.width * 0.65;
    expect(
      faceWindowGuidance(window, faceWidth: fill, centreX: 0.5 + window.width * 0.3, centreY: 0.5),
      'off_centre',
    );
    expect(
      faceWindowGuidance(window, faceWidth: fill, centreX: 0.5, centreY: 0.5 - window.height * 0.3),
      'off_centre',
    );
  });

  test('a detector that reports no centre cannot say the face drifted', () {
    expect(faceWindowGuidance(window, faceWidth: window.width * 0.65), isNull);
  });

  test('a turn or a nod may leave the centre and measure narrower', () {
    expect(
      faceWindowGuidance(
        window,
        faceWidth: window.width * 0.35,
        centreX: 0.5 + window.width * 0.3,
        centreY: 0.5,
        moving: true,
      ),
      isNull,
    );
    // Too close stays strict whatever the gesture.
    expect(
      faceWindowGuidance(window, faceWidth: window.width, moving: true),
      'too_close',
    );
  });

  // The same vectors as the web and React Native SDKs' tests.
  group('livenessWindowDrop', () {
    test('leaves the window at the centre on a tall phone', () {
      expect(
        livenessWindowDrop(const Size(440, 956), const Size(280, 369.6)),
        0,
      );
    });

    test('drops it on a short phone, by no more than the cap', () {
      expect(
        livenessWindowDrop(const Size(375, 667), const Size(232, 306.82)),
        10,
      );
      expect(
        livenessWindowDrop(const Size(320, 568), const Size(198, 261.28)),
        17,
      );
      expect(
        livenessWindowDrop(const Size(320, 480), const Size(200, 264), 60),
        0,
      );
      expect(
        livenessWindowDrop(const Size(360, 700), const Size(244, 322.08), 100),
        kLivenessWindowMaxDrop,
      );
    });

    test('counts the status bar in the room wanted above', () {
      const frame = Size(360, 780);
      const window = Size(264, 348.48);
      expect(livenessWindowDrop(frame, window), 0);
      expect(livenessWindowDrop(frame, window, 36), 10);
    });

    test('never takes the room the step count needs below', () {
      expect(livenessWindowDrop(const Size(320, 400), const Size(139, 184)), 0);
    });

    test('moves the face check with the window', () {
      const screen = Size(320, 568);
      const size = Size(198, 261.28);
      final dropped = faceWindowFor(
        screen: screen,
        window: size,
        frameAspect: 9 / 16,
        drop: livenessWindowDrop(screen, size),
      );
      expect(dropped.centreY, closeTo(0.5 + 17 / 568.889, 0.001));
      expect(
        faceWindowGuidance(
          dropped,
          faceWidth: dropped.width * 0.6,
          centreX: 0.5,
          centreY: dropped.centreY,
        ),
        isNull,
      );
      expect(
        faceWindowGuidance(
          dropped,
          faceWidth: dropped.width * 0.6,
          centreX: 0.5,
          centreY: dropped.centreY - dropped.height * 0.3,
        ),
        'off_centre',
      );
    });

    test('keeps the smallest picture and its words on a very short phone', () {
      expect(livenessAboveHeight(96), 122);
      expect(livenessAboveHeight(180), 180);
      expect(livenessGestureSize(40, 76), kLivenessGestureMinSize);
    });
  });
}
