
import 'package:flutter/services.dart';

// ─── The chip portrait ────────────────────────────────────────────────────────
//
// DG2 wraps an ISO/IEC 19794-5 facial record inside CBEFF templates, with the
// actual photo at the end as JPEG or JPEG 2000. Rather than parse the nested
// TLV (it varies by issuer), we scan for the image's own magic bytes and slice
// from there — the same approach the server takes, and it degrades safely: no
// marker means no preview, never an error.
//
// Most passports use JPEG 2000, which Flutter cannot render. iOS can: its
// ImageIO registers `public.jpeg-2000`, so a small native call decodes it to
// something displayable. Android's BitmapFactory has no JPEG 2000 decoder at
// all, so there the preview appears only for the minority of documents whose
// DG2 is baseline JPEG. A missing preview is never an error — the chip read
// itself is unaffected either way.

enum Dg2Format { jp2, j2k, jpeg }

class Dg2Image {
  final Uint8List bytes;
  final Dg2Format format;

  const Dg2Image(this.bytes, this.format);

  /// Whether Flutter can render [bytes] directly.
  bool get isDisplayable => format == Dg2Format.jpeg;
}

const _signatures = <(Dg2Format, List<int>)>[
  // JP2 file format: the ISO/IEC 15444-1 signature box.
  (
    Dg2Format.jp2,
    [0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a]
  ),
  // Raw JPEG 2000 codestream: SOC + SIZ markers.
  (Dg2Format.j2k, [0xff, 0x4f, 0xff, 0x51]),
  // Baseline JPEG: SOI + the first marker.
  (Dg2Format.jpeg, [0xff, 0xd8, 0xff]),
];

/// Locates the portrait inside a DG2 elementary file, or null when no known
/// image signature is present.
Dg2Image? extractDg2Image(Uint8List dg2) {
  Dg2Format? bestFormat;
  var bestIndex = -1;

  for (final (format, magic) in _signatures) {
    final index = _indexOf(dg2, magic);
    if (index != -1 && (bestIndex == -1 || index < bestIndex)) {
      bestIndex = index;
      bestFormat = format;
    }
  }

  if (bestFormat == null) return null;
  return Dg2Image(Uint8List.sublistView(dg2, bestIndex), bestFormat);
}

int _indexOf(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return -1;
  final limit = haystack.length - needle.length;
  outer:
  for (var i = 0; i <= limit; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

const _channel = MethodChannel('kyc_sdk_flutter/image_decode');

/// Returns renderable bytes for the chip portrait, or null when this platform
/// cannot decode the format it is in.
///
/// Best-effort by contract: the portrait is a courtesy preview, and the chip
/// read stands on its own whether or not it can be shown.
Future<Uint8List?> decodeDg2Portrait(Uint8List dg2) async {
  final image = extractDg2Image(dg2);
  if (image == null) return null;
  if (image.isDisplayable) return image.bytes;

  try {
    final decoded = await _channel.invokeMethod<Uint8List>(
      'decode',
      {'bytes': image.bytes},
    );
    return decoded;
  } on PlatformException {
    return null; // format the platform declines to decode
  } on MissingPluginException {
    return null; // older host, or a platform without the channel
  }
}
