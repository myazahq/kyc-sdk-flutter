import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/liveness_immersive.dart';

// ─── The full-screen liveness camera's own widgets ───────────────────────────

Widget _app(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    );

Future<void> _setScreen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('back and close', () {
    testWidgets('a screen reader can press them', (tester) async {
      final handle = tester.ensureSemantics();
      var backs = 0;
      var closes = 0;
      await tester.pumpWidget(_app(LivenessImmersiveControls(
        onBack: () => backs++,
        onClose: () => closes++,
      )));

      // Regression: the buttons were named for a screen reader with their
      // children excluded, which dropped the only tap action they had.
      for (final label in ['Back', 'Close']) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: label);
        expect(node.getSemanticsData().flagsCollection.isButton, isTrue,
            reason: label);
      }
      tester.semantics.tap(find.semantics.byLabel('Back'));
      tester.semantics.tap(find.semantics.byLabel('Close'));
      expect(backs, 1);
      expect(closes, 1);
      handle.dispose();
    });

    testWidgets('a tap fires once', (tester) async {
      var backs = 0;
      await tester.pumpWidget(
          _app(LivenessImmersiveControls(onBack: () => backs++)));
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump();
      expect(backs, 1);
    });
  });

  group('the instruction', () {
    testWidgets('is announced as it changes', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(
        const LivenessInstructionPill(text: 'Kindly turn your head'),
      ));
      final node =
          tester.getSemantics(find.bySemanticsLabel('Kindly turn your head'));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('a warning carries a mark, not only its colour',
        (tester) async {
      await tester.pumpWidget(_app(const LivenessInstructionPill(
        text: 'Kindly move closer',
        tone: LivenessInstructionTone.warning,
      )));
      expect(find.byType(Icon).evaluate().length +
              find.byWidgetPredicate((w) => '${w.runtimeType}' == 'MyazaIcon')
                  .evaluate()
                  .length,
          greaterThan(0));
    });

    testWidgets('a prompt shows the gesture it was handed', (tester) async {
      await tester.pumpWidget(_app(const LivenessInstructionPill(
        text: 'Smile please',
        leading: SizedBox(key: Key('gesture'), width: 28, height: 28),
      )));
      expect(find.byKey(const Key('gesture')), findsOneWidget);
    });
  });

  group('the frame', () {
    Widget frame({
      void Function(Size)? onSize,
      void Function(Size)? onWindow,
      void Function(double)? onRoom,
    }) =>
        LivenessImmersiveFrame(
          preview: const ColoredBox(color: Colors.black),
          onSize: onSize,
          cutout: (window) {
            onWindow?.call(window);
            return SizedBox.fromSize(size: window);
          },
          above: (room, _) {
            onRoom?.call(room);
            // Taller than any phone's room above the window.
            return const SizedBox(height: 400, child: Placeholder());
          },
          below: const SizedBox.shrink(),
        );

    testWidgets('sizes the window from its own box, not the screen',
        (tester) async {
      await _setScreen(tester, const Size(800, 900));
      Size? box;
      Size? window;
      // Half the display, as in a split view.
      await tester.pumpWidget(_app(
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 320,
            height: 600,
            child: frame(onSize: (s) => box = s, onWindow: (w) => window = w),
          ),
        ),
        size: const Size(800, 900),
      ));
      expect(box, const Size(320, 600));
      expect(window, livenessCutout(const Size(320, 600)));
      expect(window, isNot(livenessCutout(const Size(800, 900))));
    });

    testWidgets('content too tall for a short phone is scaled, never spilled',
        (tester) async {
      await _setScreen(tester, const Size(320, 568));
      double? room;
      await tester.pumpWidget(_app(
        frame(onRoom: (r) => room = r),
        size: const Size(320, 568),
      ));
      expect(tester.takeException(), isNull);
      expect(room, isNotNull);
      expect(room!, lessThan(kLivenessRoomForGesture));
      // Nothing is drawn above the top of the back and close buttons: the
      // block may stand between them, never over the status bar.
      final top = tester.getTopLeft(find.byType(Placeholder)).dy;
      expect(top, greaterThanOrEqualTo(8));
    });

    testWidgets('a flat tint stands in when the blur is off', (tester) async {
      await tester.pumpWidget(_app(
        LivenessBlurScope(enabled: false, child: frame()),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(_app(
        LivenessBlurScope(enabled: true, child: frame()),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  test('the scan no longer holds the camera for over a second', () {
    expect(kLivenessScanHoldMs, lessThanOrEqualTo(1000));
  });

  test('the gesture picture is full size with room, shrinks with less, and never goes into the pill', () {
    expect(livenessGestureSize(220, 76), 76);
    expect(livenessGestureSize(150, 76), 76);
    expect(livenessGestureSize(120, 76), 56);
    expect(livenessGestureSize(90, 76), kLivenessGestureMinSize);
    expect(livenessGestureSize(0, 76), kLivenessGestureMinSize);
    expect(livenessGestureSize(220, 52), kLivenessGestureMinSize);
    expect(livenessGestureSize(170, 96), 96);
    expect(livenessGestureSize(140, 96), 74);
  });
}
