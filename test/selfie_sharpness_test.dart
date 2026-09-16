import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myaza_kyc_sdk_flutter/src/utils/selfie_sharpness.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/selfie_soft_notice.dart';

// ─── The selfie focus check ──────────────────────────────────────────────────
//
// A port of the web and RN selfie-sharpness tests, plus the review notice. A
// wrong answer here only ever shows up as a notice nobody sees, or one that
// nags about a good photo, so both directions are pinned.

const _w = 64;
const _h = 48;

List<int> _plane(int Function(int x, int y) f) => [
      for (var y = 0; y < _h; y++)
        for (var x = 0; x < _w; x++) f(x, y).clamp(0, 255),
    ];

Uint8List _jpeg({required int blurRadius}) {
  final im = img.Image(width: 640, height: 480);
  for (var y = 0; y < 480; y++) {
    for (var x = 0; x < 640; x++) {
      final v = ((x ~/ 16) + (y ~/ 16)).isEven ? 0 : 255;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  final out = blurRadius > 0 ? img.gaussianBlur(im, radius: blurRadius) : im;
  return Uint8List.fromList(img.encodeJpg(out, quality: 95));
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('shared constants', () {
    test('match the web and RN mirrors', () {
      expect(kSelfieSharpnessFloor, 18);
      expect(kSelfieCropFraction, 0.5);
      expect(kSelfieMeasureSize, 160);
    });
  });

  group('laplacianVariance', () {
    test('is zero on a flat plane, whatever its brightness', () {
      expect(laplacianVariance(_plane((_, __) => 0), _w, _h), 0);
      expect(laplacianVariance(_plane((_, __) => 200), _w, _h), 0);
    });

    test('is zero on a linear gradient', () {
      expect(laplacianVariance(_plane((x, _) => x * 3), _w, _h), 0);
    });

    test('scores hard edges far above the same pattern softened', () {
      final sharp = laplacianVariance(
          _plane((x, _) => (x ~/ 4).isEven ? 0 : 255), _w, _h);
      final soft = laplacianVariance(
          _plane((x, _) => (127.5 + 127.5 * _sin(x)).round()), _w, _h);
      expect(sharp, greaterThan(soft * 10));
    });

    test('refuses a plane too small for the kernel, or a truncated buffer', () {
      expect(laplacianVariance(List.filled(4, 0), 2, 2), 0);
      expect(laplacianVariance(List.filled(_w * 4, 0), _w, _h), 0);
    });
  });

  group('selfieCentreCrop', () {
    test('takes a centred square of half the shorter side', () {
      final a = selfieCentreCrop(640, 480);
      expect((a.x, a.y, a.side), (200, 120, 240));
      final b = selfieCentreCrop(480, 640);
      expect((b.x, b.y, b.side), (120, 200, 240));
    });

    test('stays inside the image', () {
      final c = selfieCentreCrop(100, 100, 1);
      expect(c.x + c.side, lessThanOrEqualTo(100));
      expect(c.y + c.side, lessThanOrEqualTo(100));
    });
  });

  group('isSelfieBlurry', () {
    test('shows the notice only below the floor', () {
      expect(isSelfieBlurry(kSelfieSharpnessFloor - 1), isTrue);
      expect(isSelfieBlurry(kSelfieSharpnessFloor), isFalse);
      expect(isSelfieBlurry(150), isFalse);
    });

    test('never calls an unmeasured selfie blurry', () {
      expect(isSelfieBlurry(null), isFalse);
    });
  });

  group('measureSelfieSharpnessBytes', () {
    test('a sharp still passes', () {
      final score = measureSelfieSharpnessBytes(_jpeg(blurRadius: 0));
      expect(score, isNotNull);
      expect(isSelfieBlurry(score), isFalse);
    });

    test('the same still, blurred, is flagged', () {
      final sharp = measureSelfieSharpnessBytes(_jpeg(blurRadius: 0))!;
      final soft = measureSelfieSharpnessBytes(_jpeg(blurRadius: 12))!;
      expect(soft, lessThan(sharp));
      expect(isSelfieBlurry(soft), isTrue);
    });

    test('bytes that are not an image answer null', () {
      expect(measureSelfieSharpnessBytes(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('SelfieSoftNotice', () {
    testWidgets('shows the warning for a soft photo', (tester) async {
      await tester.pumpWidget(_host(SelfieSoftNotice(
        selfieBase64: 'soft',
        measure: (_) async => 5,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(kSelfieSoftTitle), findsOneWidget);
      expect(find.text(kSelfieSoftMessage), findsOneWidget);
    });

    testWidgets('says nothing about a sharp or unmeasured photo', (tester) async {
      await tester.pumpWidget(_host(SelfieSoftNotice(
        selfieBase64: 'sharp',
        measure: (_) async => 80,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(kSelfieSoftTitle), findsNothing);

      await tester.pumpWidget(_host(SelfieSoftNotice(
        selfieBase64: 'unmeasured',
        measure: (_) async => null,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(kSelfieSoftTitle), findsNothing);
    });

    testWidgets('a restored session with no preview never measures', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(SelfieSoftNotice(
        selfieBase64: null,
        measure: (_) async {
          calls++;
          return 5;
        },
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      expect(find.text(kSelfieSoftTitle), findsNothing);
    });

    testWidgets('a late answer for a retaken photo is dropped', (tester) async {
      final first = Completer<double?>();
      final second = Completer<double?>();
      Future<double?> measure(String photo) =>
          photo == 'first' ? first.future : second.future;

      await tester.pumpWidget(
          _host(SelfieSoftNotice(selfieBase64: 'first', measure: measure)));
      await tester.pumpWidget(
          _host(SelfieSoftNotice(selfieBase64: 'second', measure: measure)));
      first.complete(5);
      second.complete(80);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(kSelfieSoftTitle), findsNothing);
    });
  });

  group('wiring', () {
    test('the selfie review places the notice', () {
      final src = File('lib/src/screens/liveness_screen.dart').readAsStringSync();
      final review = src.indexOf('class _SelfieReviewView');
      final notice = src.indexOf('SelfieSoftNotice(selfieBase64: selfieBase64)');
      final next = src.indexOf('class _InstructionBanner');
      expect(review, greaterThan(-1));
      expect(notice, greaterThan(review));
      expect(notice, lessThan(next));
    });

    test('the copy is in house style', () {
      expect('$kSelfieSoftTitle $kSelfieSoftMessage', isNot(contains('—')));
    });
  });
}

// A sine sampled at an 8 pixel period, for the softened pattern.
double _sin(int x) {
  const period = 8;
  final t = (x % period) / period;
  // Triangle-free smooth wave from the Taylor-free identity via cos table.
  const table = [0.0, 0.7071, 1.0, 0.7071, 0.0, -0.7071, -1.0, -0.7071];
  return table[(t * period).round() % period];
}
