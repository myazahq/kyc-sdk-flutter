import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/document_capture_check.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/document_capture_check_notice.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/myaza_button.dart';

// ─── Document capture check ───────────────────────────────────────────────────
//
// The server reads each uploaded side with the detectors it decides with. What
// is pinned here: only a definite `false` asks for a retake, the order the
// retakes are asked for in, the copy (word for word with the web and React
// Native SDKs), and that the notice always leaves a way through.
//
// The review footer itself is not pumped: DocumentCaptureScreen needs a camera,
// platform channels and the provider tree. The notice it renders is.

const _noFace = CaptureProblemKind.noFace;
const _noBarcode = CaptureProblemKind.noBarcode;

DocumentCaptureCheckResult _result(String side, {bool? face, bool? barcode}) =>
    DocumentCaptureCheckResult(side: side, face: face, barcode: barcode);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

void main() {
  group('captureCheckProblems', () {
    test('sides that read fine ask for nothing', () {
      expect(
        captureCheckProblems(
            [_result('front', face: true), _result('back', barcode: true)]),
        isEmpty,
      );
    });

    test('an unanswered check asks for nothing', () {
      // null = the call failed or timed out; null flags = not applicable or
      // the server could not look. None of those may block the applicant.
      expect(captureCheckProblems([null, null]), isEmpty);
      expect(captureCheckProblems([_result('front'), _result('back')]), isEmpty);
      expect(captureCheckProblems(const []), isEmpty);
    });

    test('a face the server could not see', () {
      expect(captureCheckProblems([_result('front', face: false)]),
          const [CaptureProblem('front', _noFace)]);
    });

    test('a barcode the server could not read', () {
      expect(captureCheckProblems([_result('back', barcode: false), null]),
          const [CaptureProblem('back', _noBarcode)]);
    });

    test('the front before the back, whatever order the answers arrive in', () {
      expect(
        captureCheckProblems(
            [_result('back', barcode: false), _result('front', face: false)]),
        const [
          CaptureProblem('front', _noFace),
          CaptureProblem('back', _noBarcode),
        ],
      );
    });

    test('on one side, a missing face before a missing barcode', () {
      expect(
        captureCheckProblems([_result('front', barcode: false, face: false)]),
        const [
          CaptureProblem('front', _noFace),
          CaptureProblem('front', _noBarcode),
        ],
      );
    });

    test('a finding carried by two answers is reported once', () {
      expect(
        captureCheckProblems(
            [_result('front', face: false), _result('front', face: false)]),
        const [CaptureProblem('front', _noFace)],
      );
    });
  });

  test('captureProblemSides lists each side once, front first', () {
    expect(
      captureProblemSides(const [
        CaptureProblem('back', _noBarcode),
        CaptureProblem('front', _noBarcode),
        CaptureProblem('front', _noFace),
      ]),
      ['front', 'back'],
    );
    expect(captureProblemSides(const []), isEmpty);
  });

  group('copy', () {
    test('the messages, word for word', () {
      expect(
        captureProblemMessage(_noFace),
        "We couldn't see the face in the photo on the front of your ID. Retake "
        'it in good light, with the ID out of any plastic cover and no glare '
        'over the photo.',
      );
      expect(
        captureProblemMessage(_noBarcode),
        "We couldn't read the barcode on the back of your ID. Retake it with "
        'the ID out of any plastic cover, flat, filling the frame and with no '
        'glare over the barcode.',
      );
    });

    test('the title and the way through', () {
      expect(kCaptureCheckTitle, 'Check your photos');
      expect(kCaptureCheckContinueAnyway, 'Continue anyway');
    });

    test('retake labels follow the capture method', () {
      expect(captureRetakeLabel('front', uploadOnly: false), 'Retake front');
      expect(captureRetakeLabel('back', uploadOnly: false), 'Retake back');
      expect(captureRetakeLabel('front', uploadOnly: true), 'Replace front');
      expect(captureRetakeLabel('back', uploadOnly: true), 'Replace back');
    });

    test('no user-facing string carries an em dash', () {
      final copy = [
        kCaptureCheckTitle,
        kCaptureCheckContinueAnyway,
        for (final kind in CaptureProblemKind.values)
          captureProblemMessage(kind),
        for (final side in ['front', 'back'])
          for (final uploadOnly in [false, true])
            captureRetakeLabel(side, uploadOnly: uploadOnly),
      ];
      for (final line in copy) {
        expect(line, isNot(contains('—')), reason: line);
      }
    });
  });

  group('DocumentCaptureCheckResult.fromJson', () {
    test('reads the answer', () {
      final r = DocumentCaptureCheckResult.fromJson(
          {'side': 'back', 'face': null, 'barcode': false});
      expect(r.side, 'back');
      expect(r.face, isNull);
      expect(r.barcode, isFalse);
    });

    test('anything but a boolean is "could not look"', () {
      final r = DocumentCaptureCheckResult.fromJson(
          {'side': 'front', 'face': 'false', 'barcode': 0});
      expect(r.face, isNull);
      expect(r.barcode, isNull);
      expect(captureCheckProblems([r]), isEmpty);
    });
  });

  test('the notice ink clears WCAG AA on its ground in both schemes', () {
    for (final scheme in [MyazaColorScheme.light, MyazaColorScheme.dark]) {
      expect(_contrast(captureNoticeInk(scheme), scheme.warningBg),
          greaterThanOrEqualTo(4.5));
    }
  });

  group('DocumentCaptureCheckNotice', () {
    testWidgets('names each problem, offers a retake per side and a way through',
        (tester) async {
      final retaken = <String>[];
      var continued = 0;
      await tester.pumpWidget(_host(DocumentCaptureCheckNotice(
        problems: const [
          CaptureProblem('front', _noFace),
          CaptureProblem('back', _noBarcode),
        ],
        uploadOnly: false,
        onRetake: retaken.add,
        onContinueAnyway: () => continued++,
      )));
      await tester.pumpAndSettle();

      expect(find.text(kCaptureCheckTitle), findsOneWidget);
      expect(find.text(captureProblemMessage(_noFace)), findsOneWidget);
      expect(find.text(captureProblemMessage(_noBarcode)), findsOneWidget);

      MyazaButton button(String label) =>
          tester.widget<MyazaButton>(find.widgetWithText(MyazaButton, label));
      expect(button('Retake front').variant, MyazaButtonVariant.primary);
      expect(button('Retake back').variant, MyazaButtonVariant.outline);
      expect(button(kCaptureCheckContinueAnyway).variant,
          MyazaButtonVariant.outline);

      await tester.tap(find.widgetWithText(MyazaButton, 'Retake back'));
      await tester.tap(find.widgetWithText(MyazaButton, 'Retake front'));
      expect(retaken, ['back', 'front']);

      await tester.tap(
          find.widgetWithText(MyazaButton, kCaptureCheckContinueAnyway));
      expect(continued, 1);
    });

    testWidgets('one side at fault offers one retake', (tester) async {
      await tester.pumpWidget(_host(DocumentCaptureCheckNotice(
        problems: const [CaptureProblem('front', _noFace)],
        uploadOnly: false,
        onRetake: (_) {},
        onContinueAnyway: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(MyazaButton, 'Retake front'), findsOneWidget);
      expect(find.widgetWithText(MyazaButton, 'Retake back'), findsNothing);
      expect(find.widgetWithText(MyazaButton, kCaptureCheckContinueAnyway),
          findsOneWidget);
    });

    testWidgets('an upload-only flow replaces rather than retakes',
        (tester) async {
      await tester.pumpWidget(_host(DocumentCaptureCheckNotice(
        problems: const [CaptureProblem('back', _noBarcode)],
        uploadOnly: true,
        onRetake: (_) {},
        onContinueAnyway: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(MyazaButton, 'Replace back'), findsOneWidget);
    });

    testWidgets('the notice is announced as it appears', (tester) async {
      await tester.pumpWidget(_host(DocumentCaptureCheckNotice(
        problems: const [CaptureProblem('front', _noFace)],
        uploadOnly: false,
        onRetake: (_) {},
        onContinueAnyway: () {},
      )));
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text(kCaptureCheckTitle),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('reduced motion shows it at once', (tester) async {
      await tester.pumpWidget(_host(
        DocumentCaptureCheckNotice(
          problems: const [CaptureProblem('front', _noFace)],
          uploadOnly: false,
          onRetake: (_) {},
          onContinueAnyway: () {},
        ),
        reduceMotion: true,
      ));

      final fades = tester.widgetList<Opacity>(find.ancestor(
          of: find.text(kCaptureCheckTitle), matching: find.byType(Opacity)));
      expect(fades.every((o) => o.opacity == 1), isTrue);
    });
  });
}
