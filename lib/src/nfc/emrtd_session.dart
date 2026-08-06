import 'dart:math';
import 'dart:typed_data';

import 'emrtd_card_access.dart';
import 'emrtd_crypto.dart';
import 'emrtd_open.dart';
import 'emrtd_pace.dart';
import 'emrtd_pace_params.dart';
import 'emrtd_read.dart';
import 'emrtd_secure_messaging.dart';

export 'emrtd_read.dart' show ApduTransceiver;

// ─── Chip session (ICAO 9303 Part 11) ─────────────────────────────────────────
//
// Opens a secured session against an eMRTD chip and reads the elementary files
// the SDK submits: DG1 (the MRZ), EF.SOD (the signed hashes) and DG2 (the
// portrait).
//
// There are two ways in. BAC derives its keys straight from the MRZ; PACE uses
// the MRZ only to unlock a fresh nonce and then agrees new keys each time. A
// chip may offer either or both, and which one this session uses is decided by
// [establishSession] — see emrtd_open.dart for the ordering and why.
//
// The transport is injected: this class only forms APDUs and interprets
// replies, which is what lets it be tested without a phone or a passport.

class EmrtdError implements Exception {
  /// `auth_failed` when access is refused — practically always a wrong MRZ key,
  /// i.e. the chip does not belong to the page that was scanned.
  final String code;
  final String message;
  const EmrtdError(this.code, this.message);
  @override
  String toString() => 'EmrtdError($code): $message';
}

/// Elementary file identifiers.
class EfId {
  static const dg1 = 0x0101;
  static const dg2 = 0x0102;
  static const sod = 0x011D;

  /// Lives at the Master File and is readable with no session at all — it is
  /// how a terminal discovers whether the chip speaks PACE.
  static const cardAccess = 0x011C;
}

class EmrtdSession {
  final ApduTransceiver _transceive;
  final Random _random;
  late final FileReader _reader = FileReader(_transceive);
  SecureMessaging? _sm;
  PaceProtocol? _pace;
  PaceOutcome? _paceOutcome;
  String? _paceDetail;

  EmrtdSession(this._transceive, {Random? random})
      : _random = random ?? Random.secure();

  bool get isOpen => _sm != null;

  /// The read length currently in use — exposed for tests, which need to show
  /// that a chip's complaint actually changed it.
  int get maxRead => _reader.maxRead;

  /// Which protocol opened the session: `pace` or `bac`. Reported alongside the
  /// chip data so the server can tell how the session was secured.
  String get accessProtocol => _pace == null ? 'bac' : 'pace';

  /// Why the session is on that protocol. Null until a session is established.
  PaceOutcome? get paceOutcome => _paceOutcome;

  /// Free-text detail for [paceOutcome] — the negotiated protocol when PACE
  /// was used, or the error when it failed.
  String? get paceDetail => _paceDetail;

  /// Selects the ePassport application (AID A0000002471001).
  Future<void> selectApplication() async {
    final res = await _transceive(Uint8List.fromList([
      0x00, 0xA4, 0x04, 0x0C, 0x07, //
      0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01,
    ]));
    _requireOk(res, 'could not select the passport application');
  }

  /// Selects the Master File, where EF.CardAccess lives.
  Future<void> selectMasterFile() async {
    final res = await _transceive(
      Uint8List.fromList([0x00, 0xA4, 0x00, 0x0C, 0x02, 0x3F, 0x00]),
    );
    _requireOk(res, 'could not select the master file');
  }

  /// Reads EF.CardAccess without a session, or null when the chip does not
  /// offer it — which simply means BAC.
  Future<Uint8List?> readCardAccess() async {
    try {
      await selectMasterFile();
      final select = await _transceive(Uint8List.fromList(
          [0x00, 0xA4, 0x02, 0x0C, 0x02, 0x01, 0x1C]));
      if (!_isOk(select)) return null;
      final read =
          await _transceive(Uint8List.fromList([0x00, 0xB0, 0x00, 0x00, 0x00]));
      if (!_isOk(read) || read.length <= 2) return null;
      return Uint8List.sublistView(read, 0, read.length - 2);
    } catch (_) {
      return null; // absent or unreadable — the caller falls back to BAC
    }
  }

  /// Opens a session, preferring whichever protocol [preferPace] selects. See
  /// [establishChipSession] for the ordering and the reasoning behind it.
  Future<void> establishSession({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
    bool? preferPace,
  }) =>
      establishChipSession(
        session: this,
        documentNumber: documentNumber,
        dateOfBirth: dateOfBirth,
        dateOfExpiry: dateOfExpiry,
        preferPace: preferPace ?? preferPaceAccess,
        onPaceOutcome: (outcome, detail) {
          _paceOutcome = outcome;
          _paceDetail = detail;
        },
      );

  /// Runs PACE against an offering from EF.CardAccess. Throws [PaceError] on
  /// failure; the caller decides whether to fall back.
  Future<void> openPaceSession({
    required PaceOffer offer,
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
  }) async {
    final seed = keySeed(
      documentNumber: documentNumber,
      dateOfBirth: dateOfBirth,
      dateOfExpiry: dateOfExpiry,
    );
    // The MRZ unlocks the chip's nonce rather than the session itself: counter
    // 3 is the password key, where BAC uses 1 and 2 for its session keys.
    final passwordKey = offer.protocol.suite.deriveKey(seed, 3);

    _sm = await runPaceEcdhGm(
      transceive: _transceive,
      protocol: offer.protocol,
      curve: paceCurveForParameterId(offer.parameterId!)!,
      passwordKey: passwordKey,
      random: _random,
    );
    _pace = offer.protocol;

    // After PACE the application must be selected through the secure channel.
    final select = _sm!.protect(
      Uint8List.fromList([0x00, 0xA4, 0x04, 0x0C]),
      data: Uint8List.fromList([0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01]),
    );
    try {
      _sm!.unprotect(await _transceive(select));
    } on SecureMessagingError catch (e) {
      _sm = null;
      _pace = null;
      throw PaceError('read_failed', 'the secured session did not hold: ${e.message}');
    }
  }

  /// Performs BAC mutual authentication and opens secure messaging.
  ///
  /// [nonce] and [keyMaterial] exist so the ICAO worked example can be replayed
  /// exactly in tests; production always uses fresh random values.
  Future<void> openSession({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
    Uint8List? nonce,
    Uint8List? keyMaterial,
  }) async {
    final seed = keySeed(
      documentNumber: documentNumber,
      dateOfBirth: dateOfBirth,
      dateOfExpiry: dateOfExpiry,
    );
    final kEnc = deriveKey(seed, 1);
    final kMac = deriveKey(seed, 2);

    // GET CHALLENGE — the chip's 8-byte nonce.
    final challenge =
        await _transceive(Uint8List.fromList([0x00, 0x84, 0x00, 0x00, 0x08]));
    _requireOk(challenge, 'the chip refused to issue a challenge');
    final rndIc = Uint8List.sublistView(challenge, 0, 8);

    final rndIfd = nonce ?? _randomBytes(8);
    final kIfd = keyMaterial ?? _randomBytes(16);

    final s = Uint8List.fromList([...rndIfd, ...rndIc, ...kIfd]);
    final eIfd = desEde2Cbc(kEnc, s, encrypt: true);
    final mIfd = retailMac(kMac, pad(eIfd));

    final res = await _transceive(Uint8List.fromList([
      0x00, 0x82, 0x00, 0x00, 0x28, ...eIfd, ...mIfd, 0x28,
    ]));
    if (!_isOk(res)) {
      // A wrong MRZ key is by far the likeliest cause, and the message the user
      // sees says exactly that. Some older chips answer 0x63CX here rather than
      // the usual refusal, meaning the same thing.
      throw const EmrtdError(
        'auth_failed',
        'the chip rejected the document details',
      );
    }

    final body = Uint8List.sublistView(res, 0, res.length - 2);
    if (body.length < 40) {
      throw const EmrtdError('read_failed', 'short authentication response');
    }
    final eIc = Uint8List.sublistView(body, 0, 32);
    final mIc = Uint8List.sublistView(body, 32, 40);
    if (!_equals(retailMac(kMac, pad(eIc)), mIc)) {
      throw const EmrtdError('auth_failed', 'chip response failed its MAC');
    }

    final decrypted = desEde2Cbc(kEnc, eIc, encrypt: false);
    final kIc = Uint8List.sublistView(decrypted, 16, 32);

    // Session keys come from the XOR of both sides' key material.
    final sessionSeed = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      sessionSeed[i] = kIfd[i] ^ kIc[i];
    }

    // SSC starts as the low half of each nonce, chip first.
    _sm = SecureMessaging(
      ksEnc: deriveKey(sessionSeed, 1),
      ksMac: deriveKey(sessionSeed, 2),
      ssc: Uint8List.fromList([
        ...Uint8List.sublistView(rndIc, 4, 8),
        ...Uint8List.sublistView(rndIfd, 4, 8),
      ]),
    );
  }

  /// Reads an elementary file whole, in chunks the chip will accept.
  Future<Uint8List> readFile(int fileId) async {
    final sm = _sm;
    if (sm == null) {
      throw const EmrtdError('read_failed', 'no secure session');
    }
    try {
      return await _reader.read(sm, fileId);
    } on FileReadError catch (e) {
      throw EmrtdError('read_failed', e.message);
    }
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  static bool _isOk(Uint8List res) =>
      res.length >= 2 &&
      res[res.length - 2] == 0x90 &&
      res[res.length - 1] == 0x00;

  static void _requireOk(Uint8List res, String message) {
    if (!_isOk(res)) throw EmrtdError('read_failed', message);
  }

  static bool _equals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
