import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/nfc/dg2_image.dart';

// ─── Finding the portrait inside DG2 ──────────────────────────────────────────
//
// DG2 wraps the photo in CBEFF templates that vary by issuer, so the image is
// located by its own magic bytes rather than by parsing the wrapper. Mirrors
// the server's extractDg2Image so both agree on what the portrait is.

Uint8List _dg2(List<int> header, List<int> image) =>
    Uint8List.fromList([...header, ...image]);

const _biometricHeader = [0x7F, 0x61, 0x82, 0x01, 0x00, 0x02, 0x01, 0x01];
const _jp2Magic = [
  0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a //
];

void main() {
  test('finds a JPEG 2000 portrait and reports the format', () {
    final dg2 = _dg2(_biometricHeader, [..._jp2Magic, 1, 2, 3]);
    final image = extractDg2Image(dg2)!;
    expect(image.format, Dg2Format.jp2);
    expect(image.bytes.first, 0x00);
    expect(image.bytes.length, _jp2Magic.length + 3);
    expect(image.isDisplayable, isFalse,
        reason: 'Flutter cannot render JPEG 2000 — it needs a native decode');
  });

  test('finds a baseline JPEG portrait, which needs no decoding', () {
    final dg2 = _dg2(_biometricHeader, [0xff, 0xd8, 0xff, 0xe0, 9, 9]);
    final image = extractDg2Image(dg2)!;
    expect(image.format, Dg2Format.jpeg);
    expect(image.isDisplayable, isTrue);
  });

  test('finds a raw JPEG 2000 codestream', () {
    final dg2 = _dg2(_biometricHeader, [0xff, 0x4f, 0xff, 0x51, 7]);
    expect(extractDg2Image(dg2)!.format, Dg2Format.j2k);
  });

  test('takes the EARLIEST signature, not the first one listed', () {
    // A JPEG that happens to sit before a JP2-looking run must still win.
    final dg2 = _dg2(
      [..._biometricHeader, 0xff, 0xd8, 0xff, 0x01],
      _jp2Magic,
    );
    expect(extractDg2Image(dg2)!.format, Dg2Format.jpeg);
  });

  test('no known signature yields null rather than an error', () {
    expect(extractDg2Image(Uint8List.fromList(_biometricHeader)), isNull);
    expect(extractDg2Image(Uint8List(0)), isNull);
  });
}
