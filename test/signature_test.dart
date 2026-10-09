import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/signature.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/supporting_documents.dart';

SignatureDrawing pad(List<List<Offset>> strokes) =>
    SignatureDrawing(strokes: strokes, width: 320, height: 160);

void main() {
  group('a signature drawn on screen', () {
    test('measures ink across strokes', () {
      final d = pad([
        [Offset.zero, const Offset(3, 4)],
        [Offset.zero, const Offset(0, 10)],
      ]);
      expect(d.inkLength, 15);
      expect(d.pointCount, 4);
    });

    test('needs real ink: a tap or a short dash is not a signature', () {
      expect(pad([]).hasSignature, isFalse);
      expect(pad([[const Offset(5, 5)]]).hasSignature, isFalse);
      // The server's own floor: 0.6 of the shorter side (96 here).
      expect(pad([[const Offset(10, 10), const Offset(105, 10)]]).hasSignature, isFalse);
      expect(pad([[const Offset(10, 10), const Offset(110, 10)]]).hasSignature, isTrue);
    });

    test('sends rounded points and drops empty strokes', () {
      final json = const SignatureDrawing(
        strokes: [[], [Offset(1.234, 5.678)]],
        width: 320.04,
        height: 160,
      ).toJson();
      expect(json, {
        'width': 320.0,
        'height': 160.0,
        'strokes': [
          [
            {'x': 1.2, 'y': 5.7},
          ],
        ],
      });
    });
  });

  group('a pad that changes size', () {
    final stroke = [const Offset(100, 300), const Offset(200, 320)];

    test('shrinks the drawing to fit when the pad gets smaller, keeping its shape', () {
      final out = rescaleStrokes([stroke], const Size(320, 360), const Size(320, 180));
      expect(out, [
        [const Offset(50, 150), const Offset(100, 160)],
      ]);
    });

    test('leaves the drawing alone when only the height grows, or before it is measured', () {
      final strokes = [stroke];
      expect(identical(rescaleStrokes(strokes, const Size(320, 180), const Size(320, 360)), strokes), isTrue);
      expect(identical(rescaleStrokes(strokes, Size.zero, const Size(320, 180)), strokes), isTrue);
    });
  });

  group('how a supporting document is provided', () {
    SupportingDocumentsConfig config(Object? capture) => SupportingDocumentsConfig.fromJson({
          'enabled': true,
          'types': [
            {'key': 'signature_specimen', 'label': 'Signature specimen', if (capture != null) 'capture': capture},
          ],
        })!;

    test('carries the capture mode, and reads an unknown one as upload', () {
      expect(resolveSupportingDocuments(config(null), const []).first.capture, SupportingDocumentCapture.upload);
      expect(resolveSupportingDocuments(config('draw'), const []).first.capture, SupportingDocumentCapture.draw);
      expect(resolveSupportingDocuments(config('draw_or_upload'), const []).first.capture,
          SupportingDocumentCapture.drawOrUpload);
      expect(resolveSupportingDocuments(config('typed'), const []).first.capture, SupportingDocumentCapture.upload);
    });

    test('the method rides the wire and saved progress only when set', () {
      const drawn = SupportingDocumentUpload(type: 'sig', mediaId: 'med_1', fileName: 'Signature', method: 'drawn');
      expect(drawn.toJson(), {'type': 'sig', 'mediaId': 'med_1', 'method': 'drawn'});
      expect(SupportingDocumentUpload.fromJson(drawn.toJson())?.method, 'drawn');
      const file = SupportingDocumentUpload(type: 'slip', mediaId: 'med_2', fileName: 'slip.pdf');
      expect(file.toJson(), {'type': 'slip', 'mediaId': 'med_2'});
      expect(SupportingDocumentUpload.fromJson({'type': 'x', 'mediaId': 'm', 'method': 'typed'})?.method, isNull);
    });
  });
}
