import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'emrtd_pace_params.dart';
import 'emrtd_secure_messaging.dart';
import 'emrtd_pace_ec.dart';
import 'emrtd_tlv.dart';

// ─── PACE, Generic Mapping over elliptic curves (ICAO 9303 Part 11, §4.4) ─────
//
// The newer way into a chip. BAC derives its keys straight from the MRZ, so an
// attacker who photographs the passport page can decrypt a recorded session
// forever. PACE instead uses the MRZ only to unlock a fresh random nonce, then
// runs a Diffie-Hellman exchange over a generator derived from it — so the
// session keys are new every time and the MRZ alone never reveals them.
//
// The handshake is four exchanges after a setup command:
//
//   0. MSE:Set AT      name the protocol and which password we hold
//   1. get nonce       chip sends a nonce encrypted under the password key
//   2. map nonce       both sides contribute a key; the nonce and the shared
//                      secret combine into a fresh generator
//   3. key agreement   a second exchange over THAT generator gives the session
//                      secret, and the session keys derive from it
//   4. mutual auth     each side proves it derived the same keys, by MACing
//                      the other's public key
//
// Steps 1–3 are sent with the command-chaining class byte; step 4 closes the
// chain. Getting that wrong makes a chip abandon the handshake midway.

/// Thrown when the chip rejects a step or its reply does not hold up.
class PaceError implements Exception {
  /// `auth_failed` when the chip refuses the password — practically always a
  /// wrong MRZ. Anything else is a protocol or transport fault.
  final String code;
  final String message;
  const PaceError(this.code, this.message);
  @override
  String toString() => 'PaceError($code): $message';
}

/// Which secret unlocks the chip. The MRZ is what this SDK always has; a Card
/// Access Number is the other option the standard allows.
enum PacePassword { mrz, can }

/// Data objects inside the dynamic authentication template, by step.
class _Do {
  static const template = 0x7C;
  static const encryptedNonce = 0x80;
  static const mappingCommand = 0x81;
  static const mappingResponse = 0x82;
  static const keyCommand = 0x83;
  static const keyResponse = 0x84;
  static const tokenCommand = 0x85;
  static const tokenResponse = 0x86;
  static const publicKey = 0x7F49;
  static const objectIdentifier = 0x06;
  static const ecPoint = 0x86;
}

typedef PaceTransceiver = Future<Uint8List> Function(Uint8List command);

/// Runs PACE-GM over an elliptic curve and returns the secured session.
Future<SecureMessaging> runPaceEcdhGm({
  required PaceTransceiver transceive,
  required PaceProtocol protocol,
  required pc.ECDomainParameters curve,
  required Uint8List passwordKey,
  PacePassword password = PacePassword.mrz,
  Random? random,
}) async {
  final rng = random ?? Random.secure();
  final suite = protocol.suite;

  // Step 0 — announce the protocol and which password we are using.
  await _exchange(
    transceive,
    Uint8List.fromList([
      0x00, 0x22, 0xC1, 0xA4, //
      // No Le: MSE:Set AT returns no data, and appending one makes it a
      // case-4 command the chip answers 0x6700 "wrong length" to. GENERAL
      // AUTHENTICATE below DOES expect data back and keeps its Le.
      ..._body([
        tlv(0x80, protocol.oid),
        tlv(0x83, Uint8List.fromList([password == PacePassword.mrz ? 1 : 2])),
      ], expectsResponse: false),
    ]),
    step: 'select',
  );

  // Step 1 — the chip's nonce, encrypted under the password key. A chip that
  // refuses here has decided the password is wrong.
  final nonceReply = await _generalAuthenticate(
    transceive,
    tlvOf(_Do.template, const []),
    last: false,
    step: 'nonce',
  );
  final encryptedNonce = _expect(nonceReply, _Do.encryptedNonce, 'nonce');
  // No unpadding: the nonce is whole blocks of random, not a padded message.
  final nonce = suite.decrypt(passwordKey, encryptedNonce);

  // Step 2 — map the nonce onto a fresh generator. Each side sends an ephemeral
  // public key; the shared point plus the nonce give a generator neither side
  // chose alone.
  final mapKey = generateKeyPair(curve, rng);
  final mapReply = await _generalAuthenticate(
    transceive,
    tlvOf(_Do.template, [tlv(_Do.mappingCommand, encodePoint(mapKey.$2))]),
    last: false,
    step: 'mapping',
  );
  final chipMapPoint = decodePoint(curve, _expect(mapReply, _Do.mappingResponse, 'mapping'));

  final shared = (chipMapPoint * mapKey.$1)!;
  final mappedGenerator = ((curve.G * toBigInt(nonce))! + shared)!;
  if (mappedGenerator.isInfinity) {
    throw const PaceError('read_failed', 'the mapped generator was degenerate');
  }

  // Step 3 — the real key agreement, over the mapped generator.
  final sessionPrivate = randomScalar(curve, rng);
  final sessionPublic = (mappedGenerator * sessionPrivate)!;
  final keyReply = await _generalAuthenticate(
    transceive,
    tlvOf(_Do.template, [tlv(_Do.keyCommand, encodePoint(sessionPublic))]),
    last: false,
    step: 'key agreement',
  );
  final chipSessionPoint =
      decodePoint(curve, _expect(keyReply, _Do.keyResponse, 'key agreement'));

  if (chipSessionPoint == sessionPublic) {
    // Identical public keys mean the exchange contributed nothing.
    throw const PaceError('read_failed', 'the chip echoed our public key');
  }

  final agreed = (chipSessionPoint * sessionPrivate)!;
  if (agreed.isInfinity) {
    throw const PaceError('read_failed', 'key agreement produced no secret');
  }
  final secret = fieldBytes(curve, agreed.x!.toBigInteger()!);

  final ksEnc = suite.deriveKey(secret, 1);
  final ksMac = suite.deriveKey(secret, 2);

  // Step 4 — each side MACs the OTHER side's public key. Matching tokens prove
  // both derived the same session keys without either revealing them.
  final ourToken =
      suite.token(ksMac, _tokenInput(protocol.oid, chipSessionPoint));
  final tokenReply = await _generalAuthenticate(
    transceive,
    tlvOf(_Do.template, [tlv(_Do.tokenCommand, ourToken)]),
    last: true,
    step: 'authentication',
  );
  final chipToken = _expect(tokenReply, _Do.tokenResponse, 'authentication');
  final expected = suite.token(ksMac, _tokenInput(protocol.oid, sessionPublic));
  if (!constantTimeEquals(chipToken, expected)) {
    throw const PaceError(
      'auth_failed',
      'the chip proved a different key — the document details do not match',
    );
  }

  // A PACE session starts its counter at zero, unlike BAC's nonce-derived one.
  return SecureMessaging(
    ksEnc: ksEnc,
    ksMac: ksMac,
    ssc: Uint8List(suite.blockSize),
    suite: suite,
  );
}

/// GENERAL AUTHENTICATE. Steps before the last are sent with the chaining class
/// byte, which tells the chip more of the same command is coming.
Future<Uint8List> _generalAuthenticate(
  PaceTransceiver transceive,
  Uint8List data, {
  required bool last,
  required String step,
}) async {
  final cmd = Uint8List.fromList([
    last ? 0x00 : 0x10, 0x86, 0x00, 0x00, //
    ..._body([data]),
  ]);
  final res = await _exchange(transceive, cmd, step: step);
  final template = parseTlv(res);
  if (template.tag != _Do.template) {
    throw PaceError('read_failed', 'the $step reply was not authentication data');
  }
  return template.value;
}

Future<Uint8List> _exchange(
  PaceTransceiver transceive,
  Uint8List command, {
  required String step,
}) async {
  final res = await transceive(command);
  if (res.length < 2) {
    throw PaceError('read_failed', 'the chip gave no answer at the $step step');
  }
  final sw = (res[res.length - 2] << 8) | res[res.length - 1];
  if (sw != 0x9000) {
    // 0x6300 and 0x63CF are how chips say the password was wrong; some older
    // ones use the latter specifically for bad session data.
    final wrongPassword = sw == 0x6300 || (sw & 0xFFF0) == 0x63C0;
    throw PaceError(
      wrongPassword ? 'auth_failed' : 'read_failed',
      wrongPassword
          ? 'the chip rejected the document details'
          : 'the chip returned ${sw.toRadixString(16).padLeft(4, '0')} '
              'at the $step step',
    );
  }
  return Uint8List.sublistView(res, 0, res.length - 2);
}

/// Lc, body, and Le only when the command actually returns data.
///
/// ISO 7816 distinguishes a command that sends data (case 3) from one that
/// sends and receives (case 4) by the presence of that trailing byte, and a
/// chip asked for a response it has none of replies 0x6700.
List<int> _body(List<Uint8List> parts, {bool expectsResponse = true}) {
  final body = BytesBuilder();
  for (final p in parts) {
    body.add(p);
  }
  final bytes = body.toBytes();
  return [bytes.length, ...bytes, if (expectsResponse) 0x00];
}

Uint8List _expect(Uint8List template, int tag, String step) {
  final found = findTlv(template, tag);
  if (found == null) {
    throw PaceError('read_failed', 'the $step reply was missing its data');
  }
  return found.value;
}

/// The object each side MACs to prove it holds the session keys: the protocol
/// identifier and the other party's public point.
Uint8List _tokenInput(Uint8List oid, pc.ECPoint point) => tlvOf(_Do.publicKey, [
      tlv(_Do.objectIdentifier, oid),
      tlv(_Do.ecPoint, encodePoint(point)),
    ]);
