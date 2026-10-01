import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/device_attestation.dart';

import 'device_intel_fakes.dart';

// ─── Device attestation + mobile signals (wire contract §2) ──────────────────
//
// The native half is faked: what is pinned here is the payload shape, the
// hashes handed to the platform, and that every failure is an OMISSION.

void main() {
  group('iOS App Attest', () {
    test('asserts with the stored key; clientDataHash is SHA-256(challenge)',
        () async {
      final native = FakeNative();
      final keys = <String?>[];
      final out = await collectAttestation(
          platform: 'ios', native: native, fetchChallenge: fetcher(keys: keys));
      expect(out, {
        'platform': 'ios',
        'kind': 'app_attest',
        'challengeId': 'ch_1',
        'keyId': 'key-1',
        'assertion': 'QVNT',
      });
      expect(keys, ['key-1']);
      expect(native.lastAttest, isFalse);
      expect(native.lastHash, sha256.convert(challengeBytes).bytes);
    });

    test('attests when the server asks, or when there is no key yet', () async {
      final native = FakeNative();
      final asked = await collectAttestation(
          platform: 'ios',
          native: native,
          fetchChallenge: fetcher(attest: true));
      expect(asked!['attestation'], 'QVRU');
      expect(asked.containsKey('assertion'), isFalse);

      native.state = {'supported': true, 'keyId': null};
      final fresh = await collectAttestation(
          platform: 'ios', native: native, fetchChallenge: fetcher());
      expect(fresh!['keyId'], 'new-key');
      expect(native.lastAttest, isTrue);
    });

    test('unsupported, refused challenge, missing answer and timeout all omit',
        () async {
      final native = FakeNative()..state = {'supported': false};
      expect(
          await collectAttestation(
              platform: 'ios', native: native, fetchChallenge: fetcher()),
          isNull);

      native.state = {'supported': true, 'keyId': 'k'};
      expect(
          await collectAttestation(
              platform: 'ios',
              native: native,
              fetchChallenge: fetcher(fail: true)),
          isNull);

      native.attestOut = {'keyId': 'k'}; // no assertion came back
      expect(
          await collectAttestation(
              platform: 'ios', native: native, fetchChallenge: fetcher()),
          isNull);

      native
        ..attestOut = null
        ..delay = const Duration(milliseconds: 200);
      expect(
          await collectAttestation(
              platform: 'ios',
              native: native,
              fetchChallenge: fetcher(),
              budget: const Duration(milliseconds: 20)),
          isNull);
    });
  });

  group('Android Play Integrity', () {
    test('requestHash is lowercase hex SHA-256 of the challenge', () async {
      final native = FakeNative();
      final out = await collectAttestation(
          platform: 'android',
          native: native,
          fetchChallenge: fetcher(),
          cloudProjectNumber: '123456789');
      expect(out, {
        'platform': 'android',
        'kind': 'play_integrity',
        'challengeId': 'ch_1',
        'token': 'pi-token',
      });
      expect(native.lastRequestHash, sha256.convert(challengeBytes).toString());
      expect(native.lastRequestHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('no cloud project: no challenge is even requested', () async {
      final keys = <String?>[];
      expect(
          await collectAttestation(
              platform: 'android',
              native: FakeNative(),
              fetchChallenge: fetcher(keys: keys)),
          isNull);
      expect(keys, isEmpty);
    });

    test('no token omits', () async {
      final native = FakeNative()..token = null;
      expect(
          await collectAttestation(
              platform: 'android',
              native: native,
              fetchChallenge: fetcher(),
              cloudProjectNumber: '1'),
          isNull);
    });
  });
}
