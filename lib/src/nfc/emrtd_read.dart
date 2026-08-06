import 'dart:typed_data';

import 'emrtd_secure_messaging.dart';

// ─── Reading elementary files (ICAO 9303 Part 11) ─────────────────────────────
//
// Split out of the session because the interesting part is not the command but
// the negotiation: how much a chip will hand over in one READ BINARY is not
// discoverable except by asking, and chips disagree about how to say no. The
// read length therefore lives here as state that adapts across a whole session,
// not as a constant.

/// Raised when a file cannot be read. Mirrors the session's error shape so the
/// caller sees one vocabulary.
class FileReadError implements Exception {
  final String message;
  const FileReadError(this.message);
  @override
  String toString() => 'FileReadError: $message';
}

/// Sends a command APDU to the chip and returns its response (including SW).
typedef ApduTransceiver = Future<Uint8List> Function(Uint8List command);

class FileReader {
  /// Conservative opening read size. Larger reads are faster but a document
  /// that cannot serve them costs a round trip to discover, and the files that
  /// matter here are small enough that the difference is imperceptible.
  static const int _defaultReadLength = 112;

  /// Enough of a file's head to decode its TLV length.
  static const int _readAheadLength = 8;

  final ApduTransceiver _transceive;
  int _maxRead = _defaultReadLength;

  FileReader(this._transceive);

  /// The read length currently in use — exposed for tests, which need to show
  /// that a chip's complaint actually changed it.
  int get maxRead => _maxRead;

  /// Reads an elementary file whole, in chunks the chip will accept.
  ///
  /// How much a chip will hand over in one READ BINARY is not fixed, and not
  /// discoverable except by asking: some documents refuse anything over 160
  /// bytes, some name their limit in the error, and some return short reads
  /// with a warning rather than an error. So the read length starts
  /// conservatively and adapts downwards from whatever the chip says. A fixed
  /// chunk size works on most passports and fails outright on the rest — which
  /// is the sort of thing that only shows up once someone else's document is in
  /// front of the phone.
  Future<Uint8List> read(SecureMessaging sm, int fileId) async {
    // SELECT by elementary file id.
    final select = sm.protect(
      Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C]),
      data: Uint8List.fromList([(fileId >> 8) & 0xFF, fileId & 0xFF]),
    );
    sm.unprotect(await _transceive(select));

    // The first read reveals the total length from the file's own TLV header.
    final head = await _readChunk(sm, 0, _readAheadLength);
    if (head.data.isEmpty) {
      throw const FileReadError('empty file header');
    }
    final total = _fileLength(head.data);

    final out = BytesBuilder()..add(head.data);
    var offset = head.data.length;
    var emptyReads = 0;

    while (offset < total) {
      var want = total - offset;
      if (want > _maxRead) want = _maxRead;
      // An ordinary READ BINARY carries the offset in 15 bits of P1/P2, so a
      // read must never straddle that boundary — past it we switch commands.
      if (offset < 0x7FFF && offset + want > 0x7FFF) want = 0x7FFF - offset;

      final SmResponse chunk;
      try {
        chunk = await _readChunk(sm, offset, want);
      } on SecureMessagingError catch (e) {
        throw FileReadError(e.message);
      }

      final sw1 = chunk.sw >> 8;
      if (chunk.sw == 0x9000 || sw1 == 0x61 || chunk.sw == 0x6281) {
        // Success, or "more bytes available", or "some of this may be
        // corrupted" — all of which come with usable data.
      } else if (chunk.sw == 0x6282) {
        // End of file reached before Le bytes: we asked for more than the chip
        // was willing to give. Keep what came back and ask for less.
        _reduceMaxRead();
      } else if (chunk.sw == 0x6700) {
        // Wrong length, and no data at all.
        if (_maxRead <= 1) {
          throw const FileReadError('the chip refused every read length');
        }
        _reduceMaxRead();
      } else if (sw1 == 0x6C) {
        // The chip named the exact length it will serve.
        final exact = chunk.sw & 0xFF;
        if (exact == 0) {
          throw const FileReadError('chip asked for a zero-byte read');
        }
        _maxRead = exact;
      } else {
        throw FileReadError(
          'chip returned ${chunk.sw.toRadixString(16).padLeft(4, '0')}',
        );
      }

      if (chunk.data.isEmpty) {
        // Guards against a chip that answers politely but never advances.
        if (++emptyReads >= 10) {
          throw const FileReadError('chip stopped returning data');
        }
        continue;
      }
      emptyReads = 0;
      out.add(chunk.data);
      offset += chunk.data.length;
    }

    // Some documents over-return on a short read (a mispadded final chunk).
    // The file's own header said how long it is; trust that.
    final bytes = out.toBytes();
    return bytes.length > total ? Uint8List.sublistView(bytes, 0, total) : bytes;
  }

  Future<SmResponse> _readChunk(
    SecureMessaging sm,
    int offset,
    int length,
  ) async {
    if (offset > 0x7FFF) {
      // Extended READ BINARY: the offset moves out of P1/P2 into the command
      // body as a TLV, and the reply comes back wrapped in tag 0x53. Needed
      // only for files over 32 KB — a high-resolution DG2 portrait can get
      // there.
      final body = Uint8List.fromList([
        0x54, 0x04, //
        (offset >> 24) & 0xFF, (offset >> 16) & 0xFF,
        (offset >> 8) & 0xFF, offset & 0xFF,
      ]);
      // Room for the 0x53 tag and its length bytes on top of the data.
      final ne = (length + 3).clamp(1, 256);
      final cmd = sm.protect(
        Uint8List.fromList([0x00, 0xB1, 0x00, 0x00]),
        data: body,
        le: ne,
        dataTag: 0x85,
      );
      final res = sm.unwrap(await _transceive(cmd));
      return (data: _unwrapTag53(res.data), sw: res.sw);
    }

    final cmd = sm.protect(
      Uint8List.fromList([
        0x00, 0xB0, (offset >> 8) & 0x7F, offset & 0xFF, //
      ]),
      le: length,
    );
    return sm.unwrap(await _transceive(cmd));
  }

  /// Unwraps the BER-TLV envelope an extended READ BINARY reply arrives in.
  static Uint8List _unwrapTag53(Uint8List data) {
    if (data.isEmpty || data[0] != 0x53) return data;
    var i = 1;
    final first = data[i++];
    var len = first;
    if (first >= 0x80) {
      final n = first & 0x7F;
      len = 0;
      for (var j = 0; j < n; j++) {
        len = (len << 8) | data[i++];
      }
    }
    final end = (i + len) > data.length ? data.length : i + len;
    return Uint8List.sublistView(data, i, end);
  }

  /// Steps the read length down the ladder of sizes real documents accept.
  void _reduceMaxRead() {
    const ladder = [224, 160, 128, 96, 64, 32, 16, 8, 1];
    for (final size in ladder) {
      if (_maxRead > size) {
        _maxRead = size;
        return;
      }
    }
    _maxRead = 1;
  }

  /// Total file size from its leading BER-TLV header (tag + length + value).
  static int _fileLength(Uint8List head) {
    var i = 1; // single-byte tags only in the LDS files we read
    if ((head[0] & 0x1F) == 0x1F) i++; // multi-byte tag, rare but cheap to allow
    final lenByte = head[i];
    if (lenByte < 0x80) return i + 1 + lenByte;
    final n = lenByte & 0x7F;
    var len = 0;
    for (var j = 0; j < n; j++) {
      len = (len << 8) | head[i + 1 + j];
    }
    return i + 1 + n + len;
  }

}
