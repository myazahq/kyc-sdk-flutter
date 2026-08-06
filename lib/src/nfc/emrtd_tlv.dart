import 'dart:typed_data';

// ─── BER-TLV, the little that eMRTD needs ─────────────────────────────────────
//
// Enough to build the PACE command bodies and take apart EF.CardAccess. Not a
// general ASN.1 library: it handles the single- and two-byte tags this protocol
// actually uses and the definite-length forms, and refuses anything else rather
// than guessing.

class TlvError implements Exception {
  final String message;
  const TlvError(this.message);
  @override
  String toString() => 'TlvError: $message';
}

class Tlv {
  final int tag;
  final Uint8List value;

  /// Offset just past this object in the buffer it was parsed from.
  final int end;

  const Tlv(this.tag, this.value, [this.end = 0]);

  /// The complete encoded object, tag and length included.
  Uint8List encode() => Uint8List.fromList([
        ...tagBytes(tag),
        ...lengthBytes(value.length),
        ...value,
      ]);
}

/// Splits a tag into its encoded bytes. Tags above 0xFF are two-byte (the
/// eMRTD protocol uses 0x7F49 for a public key and 0x5F1E and friends in the
/// data groups); anything larger is not used here.
List<int> tagBytes(int tag) =>
    tag > 0xFF ? [(tag >> 8) & 0xFF, tag & 0xFF] : [tag & 0xFF];

/// Definite-length encoding, short form up to 127 then 0x81/0x82.
List<int> lengthBytes(int n) {
  if (n < 0x80) return [n];
  if (n <= 0xFF) return [0x81, n];
  return [0x82, (n >> 8) & 0xFF, n & 0xFF];
}

/// Builds one object.
Uint8List tlv(int tag, Uint8List value) => Tlv(tag, value).encode();

/// Builds one object whose value is a concatenation of others.
Uint8List tlvOf(int tag, List<Uint8List> parts) {
  final body = BytesBuilder();
  for (final p in parts) {
    body.add(p);
  }
  return tlv(tag, body.toBytes());
}

/// Reads the object starting at [offset].
Tlv parseTlv(Uint8List data, [int offset = 0]) {
  if (offset >= data.length) throw const TlvError('no data');
  var i = offset;
  var tag = data[i++];
  // A leading 0x1F in the tag's low bits means the tag continues into the next
  // byte. 0x7F49 (the public-key object) is the case that matters here.
  if ((tag & 0x1F) == 0x1F) {
    if (i >= data.length) throw const TlvError('truncated tag');
    tag = (tag << 8) | data[i++];
  }

  if (i >= data.length) throw const TlvError('truncated length');
  var len = data[i++];
  if (len >= 0x80) {
    final n = len & 0x7F;
    if (n == 0 || n > 3) throw const TlvError('unsupported length form');
    if (i + n > data.length) throw const TlvError('truncated length');
    len = 0;
    for (var j = 0; j < n; j++) {
      len = (len << 8) | data[i++];
    }
  }

  if (i + len > data.length) throw const TlvError('truncated value');
  return Tlv(tag, Uint8List.sublistView(data, i, i + len), i + len);
}

/// Reads every object in [data], in order.
List<Tlv> parseTlvSequence(Uint8List data) {
  final out = <Tlv>[];
  var offset = 0;
  while (offset < data.length) {
    final t = parseTlv(data, offset);
    out.add(t);
    if (t.end <= offset) break; // defensive: never spin on a zero-width read
    offset = t.end;
  }
  return out;
}

/// Finds the first object with [tag] directly inside [data].
Tlv? findTlv(Uint8List data, int tag) {
  try {
    for (final t in parseTlvSequence(data)) {
      if (t.tag == tag) return t;
    }
  } on TlvError {
    return null;
  }
  return null;
}

/// Reads a DER INTEGER's value as an int. eMRTD only uses these for small
/// numbers — protocol versions and parameter ids.
int? tlvInt(Uint8List value) {
  if (value.isEmpty || value.length > 4) return null;
  var n = 0;
  for (final b in value) {
    n = (n << 8) | b;
  }
  return n;
}
