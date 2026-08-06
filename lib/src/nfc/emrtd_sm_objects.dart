import 'dart:typed_data';

// ─── Taking a secure-messaging response apart ─────────────────────────────────
//
// A protected response is a run of BER-TLV data objects: optionally the
// encrypted data, the chip's real status word, and the MAC. Splitting them is
// pure byte-work with no keys involved, so it lives here where it can be read
// and tested on its own.

class ResponseObjectsError implements Exception {
  final String message;
  const ResponseObjectsError(this.message);
  @override
  String toString() => 'ResponseObjectsError: $message';
}

/// The parts of a protected response.
typedef ResponseObjects = ({
  /// Ciphertext from DO'87' or DO'85', with any padding-content indicator
  /// already stripped. Null when the response carried no data.
  Uint8List? encrypted,

  /// The MAC from DO'8E'. Null when absent, which makes the response unusable.
  Uint8List? mac,

  /// The status word from DO'99', if present.
  int? statusWord,

  /// Everything the MAC covers: all objects before DO'8E', in order.
  Uint8List macCovered,
});

/// Splits [body] — a response with its outer status word already removed.
ResponseObjects splitResponseObjects(Uint8List body) {
  Uint8List? encrypted;
  Uint8List? mac;
  int? statusWord;
  final covered = BytesBuilder();

  var i = 0;
  while (i < body.length) {
    final tag = body[i];
    final (len, headerLen) = readBerLength(body, i + 1);
    final valueStart = i + 1 + headerLen;
    if (valueStart + len > body.length) {
      throw const ResponseObjectsError('truncated data object');
    }
    final value = Uint8List.sublistView(body, valueStart, valueStart + len);

    if (tag == 0x8E) {
      mac = value;
      // Everything BEFORE DO'8E' is what the MAC covers.
    } else {
      covered.add(Uint8List.sublistView(body, i, valueStart + len));
      if (tag == 0x87 && value.isNotEmpty) {
        // Skip the leading padding-content indicator.
        encrypted = Uint8List.sublistView(value, 1);
      } else if (tag == 0x85) {
        // Extended READ BINARY replies carry the data unindicated.
        encrypted = value;
      } else if (tag == 0x99 && len == 2) {
        statusWord = (value[0] << 8) | value[1];
      }
    }
    i = valueStart + len;
  }

  return (
    encrypted: encrypted,
    mac: mac,
    statusWord: statusWord,
    macCovered: covered.toBytes(),
  );
}

/// BER length bytes for a value of [n] bytes (short and 0x81 forms only — no
/// data object this protocol builds exceeds 255 bytes).
List<int> berLengthBytes(int n) => n < 0x80 ? [n] : [0x81, n];

/// Reads a BER length at [offset]; returns (value, bytes consumed).
(int, int) readBerLength(Uint8List data, int offset) {
  if (offset >= data.length) {
    throw const ResponseObjectsError('truncated length');
  }
  final first = data[offset];
  if (first < 0x80) return (first, 1);
  if (first == 0x81) return (data[offset + 1], 2);
  if (first == 0x82) return ((data[offset + 1] << 8) | data[offset + 2], 3);
  throw const ResponseObjectsError('unsupported length encoding');
}
