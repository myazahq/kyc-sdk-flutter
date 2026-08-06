import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../nfc/emrtd_session.dart';
import 'nfc_reader.dart';

// ─── eMRTD chip reader (our own BAC implementation) ───────────────────────────
//
// Replaces the dmrtd package. The protocol lives in lib/src/nfc/ and is checked
// against the worked example published in ICAO 9303 Part 11 Appendix D — the
// session keys, the send-sequence counter and the protected APDUs all match the
// standard byte for byte, which is what makes a from-scratch implementation of
// a security protocol defensible.
//
// The read order is deliberate and unchanged from before: DG1 first (tiny, and
// the one file the server always needs), then EF.SOD (kilobytes, and what
// passive authentication verifies), then DG2 (the portrait, largest and the
// most likely to drop if the document is lifted). Everything after DG1 is
// best-effort, because a partial read is worth more than no read.

class EmrtdNfcChipReader implements NfcChipReader {
  @override
  Future<bool> isAvailable() async {
    try {
      return (await FlutterNfcKit.nfcAvailability) == NFCAvailability.available;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NfcChipData> read(
    NfcMrzKey key, {
    String iosAlertMessage = 'Hold your phone near the document’s chip',
    void Function(NfcReadStage stage)? onStage,
  }) async {
    var connected = false;
    try {
      onStage?.call(NfcReadStage.waiting);
      // Blocks until the document is actually against the phone.
      await FlutterNfcKit.poll(
        iosAlertMessage: iosAlertMessage,
        readIso14443A: true,
        readIso14443B: true,
        readIso15693: false,
        readIso18092: false,
      );
      connected = true;

      final session = EmrtdSession(
        (cmd) async => await FlutterNfcKit.transceive<Uint8List>(cmd),
      );

      // The session is retried once, because on Android the FIRST attempt
      // routinely fails and an immediate second succeeds with the phone
      // untouched — the tag is dispatched while the platform is still settling
      // the link, so the first exchange dies with the chip right there.
      Object? lastError;
      var opened = false;
      for (var attempt = 0; attempt < 2 && !opened; attempt++) {
        try {
          onStage?.call(
            attempt == 0 ? NfcReadStage.waiting : NfcReadStage.authenticating,
          );
          onStage?.call(NfcReadStage.authenticating);
          // Tries BAC then PACE — see emrtd_open.dart for why that order.
          await session.establishSession(
            documentNumber: key.documentNumber,
            dateOfBirth: _yymmdd(key.dateOfBirth),
            dateOfExpiry: _yymmdd(key.dateOfExpiry),
          );
          opened = true;
        } catch (e) {
          lastError = e;
        }
      }
      if (!opened) {
        // A wrong MRZ key fails both attempts; keep that distinction, because
        // the message the user sees depends on it.
        if (lastError is EmrtdError && lastError.code == 'auth_failed') {
          throw NfcReadException('auth_failed', lastError.message);
        }
        throw NfcReadException('read_failed', lastError?.toString() ?? 'failed');
      }

      onStage?.call(NfcReadStage.readingData);
      final dg1 = await session.readFile(EfId.dg1);

      // EF.SOD is what passive authentication verifies, so losing it costs the
      // strongest assurance tier — but it is kilobytes against DG1's ~90 bytes
      // and needs seconds more contact, so it gets its own retry.
      Uint8List? sod;
      String? sodError;
      onStage?.call(NfcReadStage.readingSecurity);
      for (var attempt = 0; attempt < 2 && sod == null; attempt++) {
        await _setAlert(attempt == 0
            ? 'Keep holding — reading security data…'
            : 'Almost there — hold the document still…');
        try {
          sod = await session.readFile(EfId.sod);
        } catch (e) {
          sodError = e.toString();
        }
      }

      // DG2 (the portrait) last: largest, likeliest to drop, and only useful
      // when the SOD came back — the server can only trust the photo by hashing
      // it against the SOD's entry.
      Uint8List? dg2;
      if (sod != null) {
        onStage?.call(NfcReadStage.readingPhoto);
        await _setAlert('Reading photo…');
        try {
          dg2 = await session.readFile(EfId.dg2);
        } catch (_) {
          // Portrait unavailable — proceed without it.
        }
      }

      onStage?.call(NfcReadStage.done);
      await _finish(message: 'Chip read complete');
      connected = false;

      return NfcChipData(
        dg1Base64: base64.encode(dg1),
        sodBase64: sod == null ? null : base64.encode(sod),
        dg2Base64: dg2 == null ? null : base64.encode(dg2),
        // STRICTLY the protocol: the server validates this against
        // ('bac'|'pace'|'none') and rejects the whole submission otherwise.
        // The PACE diagnostic travels in its own field.
        chipAuth: session.accessProtocol,
        paceOutcome: session.paceOutcome?.name,
        paceDetail: session.paceDetail,
        sodError: sod == null ? sodError : null,
      );
    } on NfcReadException {
      if (connected) await _finish(error: 'Chip read failed');
      rethrow;
    } catch (e) {
      if (connected) await _finish(error: 'Chip read failed');
      throw NfcReadException('read_failed', e.toString());
    }
  }

  /// BAC hashes the MRZ dates as YYMMDD.
  static String _yymmdd(DateTime d) {
    final y = (d.year % 100).toString().padLeft(2, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y$m$day';
  }

  static Future<void> _setAlert(String message) async {
    try {
      await FlutterNfcKit.setIosAlertMessage(message);
    } catch (_) {
      // Android has no session alert; the SDK draws its own sheet.
    }
  }

  static Future<void> _finish({String? message, String? error}) async {
    try {
      await FlutterNfcKit.finish(
        iosAlertMessage: message,
        iosErrorMessage: error,
      );
    } catch (_) {
      // already closed
    }
  }
}

/// Returns the reader to use — the test override when set, else the real chip
/// reader. The single construction point for the native reader.
NfcChipReader createNfcChipReader() =>
    nfcChipReaderOverride ?? EmrtdNfcChipReader();
