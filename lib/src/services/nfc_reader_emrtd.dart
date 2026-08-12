import 'dart:async';
import 'dart:convert';

// Also re-exports dart:typed_data (Uint8List), so that import would be flagged
// as redundant. Brought in for debugPrint: unlike print, it is rate-limited by
// the framework and can be silenced by the host app's logging config.
import 'package:flutter/foundation.dart';
// PlatformException: how flutter_nfc_kit reports a poll timeout (code '408').
import 'package:flutter/services.dart';
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
      await _pollForTag(iosAlertMessage, onStage);
      connected = true;
      _log('tag acquired');
      return await _readOpenedChip(key, onStage, () => connected = false);
    } on NfcReadException {
      if (connected) await _finish(error: 'Chip read failed');
      rethrow;
    } catch (e) {
      _log('read FAILED: $e');
      if (connected) await _finish(error: 'Chip read failed');
      throw NfcReadException('read_failed', e.toString());
    }
  }

  /// Wait for the document, in SHORT windows rather than one long one.
  ///
  /// A single 20s poll was the whole user-visible bug. Android's own tag
  /// dispatch consumes a document presented before our reader mode starts, and
  /// it does not re-deliver a tag that stayed in the field — so `poll()` waits
  /// out its entire timeout against a chip that is physically touching the
  /// phone, then fails with `408 Polling tag timeout`. Captured on a Galaxy S24:
  ///
  ///   11:25:26  read FAILED: PlatformException(408, Polling tag timeout)
  ///   11:25:28  tag acquired            ← after a lift-and-replace
  ///   11:25:42  session opened over pace
  ///
  /// Short windows do not make Android deliver the tag. What they buy is the
  /// chance to TELL the user the one thing that recovers it, ~14 seconds sooner
  /// and without the read failing first.
  Future<void> _pollForTag(
    String iosAlertMessage,
    void Function(NfcReadStage stage)? onStage,
  ) async {
    final deadline = DateTime.now().add(_totalPollTimeout);
    for (var window = 0;; window++) {
      try {
        await _pollOnce(iosAlertMessage, _pollWindow);
        return;
      } catch (e) {
        if (!_isPollTimeout(e) || DateTime.now().isAfter(deadline)) rethrow;
        // Not an error yet: on the first miss the document may simply not be
        // there. From the second, it very likely IS there and unreachable.
        _log('poll window ${window + 1} timed out; asking for a reposition');
        onStage?.call(NfcReadStage.repositionNeeded);
      }
    }
  }

  /// One polling window.
  Future<void> _pollOnce(String iosAlertMessage, Duration timeout) async {
    await FlutterNfcKit.poll(
      timeout: timeout,
      iosAlertMessage: iosAlertMessage,
      readIso14443A: true,
      readIso14443B: true,
      readIso15693: false,
      readIso18092: false,
      // SKIP THE NDEF PROBE. This is what made the first tap fail on Android.
      //
      // `androidCheckNDEF` defaults to TRUE, which sets Android's NDEF-format
      // check. That probe connects to EACH of the tag's technologies in turn,
      // and moving from tech 0 to tech 1 forces an RF interface switch from
      // ISO-DEP to FRAME — which drops a passport chip. Captured on a Galaxy
      // S24, every failed tap read:
      //
      //   doConnect: targetIdx=0 → doIsIsoDepNdefFormatable
      //   doConnect: targetIdx=1 → "switching to tech=1 need to switch rf
      //                             intf to frame" → doIsIsoDepNdefFormatable
      //   Tag lost, restarting polling loop
      //
      // with NO transceive in between — the link died before a single APDU,
      // so neither the protocol nor the in-place session retry could help.
      // A passport is never an NDEF tag, so the probe can only ever cost us.
      //
      // Maps to NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK (0x80); the plugin does
      // NOT set it by default. The React Native SDK passes the same flag to
      // enableReaderMode, which is why Android reads there succeed first time.
      androidCheckNDEF: false,
      // How long Android waits between "is the tag still there?" probes.
      // Generous on purpose: the probes interleave with ISO-DEP traffic, and
      // the ~125ms default is a known cause of chips dropping partway through
      // a large DG2 read. The read has its own timeout, so a tag genuinely
      // removed is still noticed. Matches the RN SDK's PRESENCE_CHECK_DELAY_MS.
      extraReaderPresenceCheckDelay: const Duration(seconds: 5),
    );
  }

  /// Everything after the tag is in hand.
  Future<NfcChipData> _readOpenedChip(
    NfcMrzKey key,
    void Function(NfcReadStage stage)? onStage,
    void Function() markFinished,
  ) async {
    {
      final session = EmrtdSession(
        // 20s per exchange, NOT the plugin's 5s default.
        //
        // DG2 is ~16KB read in ~200-byte chunks over a link the user is holding
        // by hand, and a chip that pauses under load is working normally, not
        // absent. The default aborts mid-file on a chip doing nothing wrong,
        // which costs the portrait and with it the DG2 face match. On Android
        // this is persistent for the session (see the plugin's `transceive`
        // doc), so it is set once here rather than per command. Matches the RN
        // SDK's `dep.timeout = 20_000`, which carries the same reasoning.
        (cmd) async => await FlutterNfcKit.transceive<Uint8List>(
          cmd,
          timeout: const Duration(seconds: 20),
        ),
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
          // The retry is the whole reason a first-attempt failure is usually
          // invisible to the user — which also made it invisible to US. A
          // swallowed error here is the difference between "Android dropped the
          // link" and "the MRZ key is wrong", and those need opposite fixes.
          _log('session attempt ${attempt + 1}/2 failed: $e');
        }
      }
      if (!opened) {
        // A wrong MRZ key fails both attempts; keep that distinction, because
        // the message the user sees depends on it.
        if (lastError is EmrtdError && lastError.code == 'auth_failed') {
          _log('read FAILED: auth_failed (both attempts) — MRZ key rejected');
          throw NfcReadException('auth_failed', lastError.message);
        }
        _log('read FAILED: read_failed (both attempts) — $lastError');
        throw NfcReadException(
            'read_failed', lastError?.toString() ?? 'failed');
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
      markFinished();

      // WHAT ACTUALLY HAPPENED, in one line.
      //
      // The protocol name alone cannot answer the question that matters while
      // PACE is new: a chip that opened over BAC may never have OFFERED PACE,
      // or may have offered it and had our implementation fail. Those call for
      // opposite responses — one is nothing to do, the other is a bug.
      //
      // This exists because diagnosing an Android read without it meant reading
      // the platform's native NFC log and correlating timestamps against the
      // server's UTC rows by hand. The React Native SDK has printed the
      // equivalent line from the start; Flutter printed nothing.
      _log(
        'session opened over ${session.accessProtocol}'
        ' (pace: ${session.paceOutcome?.name ?? 'n/a'}'
        '${session.paceDetail == null ? '' : ' — ${session.paceDetail}'})'
        ' · sod=${sod == null ? 'missing' : '${sod.length}B'}'
        ' · dg2=${dg2 == null ? 'missing' : '${dg2.length}B'}',
      );

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
    }
  }

  /// A polling window that expired. flutter_nfc_kit reports it as a platform
  /// error with code 408, and iOS surfaces its own session timeout, so match on
  /// both rather than on prose.
  static bool _isPollTimeout(Object e) =>
      e is TimeoutException ||
      (e is PlatformException && (e.code == '408' || e.code == '500'));

  /// One wait before we offer an instruction. Long enough that a user still
  /// reaching for their document is not nagged, short enough to be useful.
  static const Duration _pollWindow = Duration(seconds: 6);

  /// How long to keep offering before giving up altogether.
  static const Duration _totalPollTimeout = Duration(seconds: 60);

  /// One prefix for every chip-read line, so a device log can be filtered to
  /// just this subsystem. Mirrors the React Native SDK's `[kyc.nfc]`.
  static void _log(String message) => debugPrint('[kyc.nfc] $message');

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
