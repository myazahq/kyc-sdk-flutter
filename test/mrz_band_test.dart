import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myaza_kyc_sdk_flutter/src/services/image_service.dart';

// ─── The MRZ band ─────────────────────────────────────────────────────────────
//
// Reading the machine-readable zone off the photo the user just took is what
// spares them scanning the same document twice for the chip step. Handing a
// general text recogniser the whole data page makes OCR-B compete with the
// printed fields, the portrait and the security pattern; handing it the bottom
// strip, enlarged, is the single biggest thing that makes it read.
//
// Reported from a Galaxy S24: "after taking a photo of the passport, I still
// had to scan the MRZ again."

Uint8List _page({int width = 900, int height = 640}) {
  final image = img.Image(width: width, height: height);
  // A distinct band at the bottom, so the crop can be checked for having taken
  // the right part of the page rather than merely the right size.
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: (height * 0.6).round(),
    x2: width - 1,
    y2: height - 1,
    color: img.ColorRgb8(0, 0, 0),
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  test('takes the BOTTOM of the page, where the MRZ is', () async {
    final band = await cropMrzBand(_page(), bandFraction: 0.3);
    expect(band, isNotNull);

    final decoded = img.decodeImage(band!)!;
    // The bottom 30% of the fixture is the black band, so a correct crop is
    // overwhelmingly dark. Cropping the top would come back white.
    final middle = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(middle.r, lessThan(60),
        reason: 'the crop must be the bottom band, not the top of the page');
  });

  test('upscales a small band so OCR-B has pixels to work with', () async {
    final band = await cropMrzBand(_page(width: 400), minWidth: 1600);
    final decoded = img.decodeImage(band!)!;
    expect(decoded.width, greaterThanOrEqualTo(1600));
  });

  test('leaves an already-large band alone', () async {
    final band = await cropMrzBand(_page(width: 2000), minWidth: 1600);
    final decoded = img.decodeImage(band!)!;
    expect(decoded.width, 2000);
  });

  test('undecodable bytes yield null rather than throwing', () async {
    // The band is one extra candidate, never a requirement — a failure here
    // must leave the full-frame attempts to run.
    expect(await cropMrzBand(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
