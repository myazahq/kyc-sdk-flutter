import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/fingerprint_payload.dart';

// ─── Device-intel wire contract: header, gate, challenge, config ─────────────

class CapturingAdapter implements HttpClientAdapter {
  CapturingAdapter(this.body, {this.status = 200});
  final Object body;
  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

KYCApiService apiWith(CapturingAdapter adapter,
        {Future<String?> Function()? deviceId}) =>
    KYCApiService(
      baseUrl: 'https://api.example',
      apiKey: 'pk_test_x',
      deviceId: deviceId,
      httpClientAdapter: adapter,
    );

Future<Map<String, dynamic>> base() async => {
      'deviceId': 'did-1',
      'components': {'platform': 'ios'}
    };

void main() {
  group('upload header', () {
    Future<Map<String, dynamic>> uploadHeaders(
        Future<String?> Function()? id) async {
      final adapter = CapturingAdapter({'mediaId': 'med_1'});
      await apiWith(adapter, deviceId: id).upload(
          Uint8List.fromList([1, 2, 3]), 'image/jpeg', MediaType.selfie);
      return adapter.requests.single.headers;
    }

    test('carries the fingerprint deviceId', () async {
      final headers = await uploadHeaders(() async => 'did-1');
      expect(headers[kDeviceIdHeader], 'did-1');
    });

    test('omitted when there is no id, it fails, or it is too long', () async {
      expect((await uploadHeaders(null)).containsKey(kDeviceIdHeader), isFalse);
      expect(
          (await uploadHeaders(() async => null)).containsKey(kDeviceIdHeader),
          isFalse);
      expect(
          (await uploadHeaders(() async => throw StateError('x')))
              .containsKey(kDeviceIdHeader),
          isFalse);
      expect(
          (await uploadHeaders(() async => 'a' * 65))
              .containsKey(kDeviceIdHeader),
          isFalse);
    });

    test('the header source exists only while Device Intelligence is on',
        () async {
      expect(uploadDeviceIdSource(deviceIntelligence: false), isNull);
      final source = uploadDeviceIdSource(
          deviceIntelligence: true, read: () async => 'did-1');
      expect(await source!(), 'did-1');
    });
  });

  group('fingerprint gate', () {
    test('off: no fingerprint, and the mobile additions are never asked for',
        () async {
      var asked = false;
      final out = await collectFingerprint(
        deviceIntelligence: false,
        base: base,
        extras: () async {
          asked = true;
          return {'stableId': 's'};
        },
      );
      expect(out, isNull);
      expect(asked, isFalse);
    });

    test('on: additions ride beside components, never inside or over them',
        () async {
      final cached = await base();
      final out = await collectFingerprint(
        deviceIntelligence: true,
        base: () async => cached,
        extras: () async => {
          'stableId': 's-1',
          'integrity': {
            'rooted': false,
            'hooked': false,
            'signals': <String>[]
          },
          'deviceId': 'forged',
          'components': {'x': 1},
        },
      );
      expect(out!['deviceId'], 'did-1');
      expect(out['components'], {'platform': 'ios'});
      expect(out['stableId'], 's-1');
      expect(out.containsKey('integrity'), isTrue);
      expect(cached.containsKey('stableId'), isFalse,
          reason: 'cache untouched');
    });

    test('failed additions leave the base fingerprint as it was', () async {
      final out = await collectFingerprint(
        deviceIntelligence: true,
        base: base,
        extras: () async => throw StateError('native down'),
      );
      expect(out, await base());
    });
  });

  group('challenge', () {
    test('posts { platform, keyId } and decodes the challenge', () async {
      final adapter = CapturingAdapter({
        'challengeId': 'ch_9',
        'challenge': base64.encode(List.filled(32, 7)),
        'expiresAt': '2026-10-01T00:00:00Z',
        'attest': true,
      });
      final ch =
          await apiWith(adapter).deviceChallenge(platform: 'ios', keyId: 'k1');
      expect(adapter.requests.single.path, '/api/kyc/device/challenge');
      expect(adapter.requests.single.data, {'platform': 'ios', 'keyId': 'k1'});
      expect(ch!.id, 'ch_9');
      expect(ch.bytes, List.filled(32, 7));
      expect(ch.attest, isTrue);
    });

    test('a 404 or a malformed body means skip', () async {
      final notFound = CapturingAdapter({'error': 'not_found'}, status: 404);
      expect(
          await apiWith(notFound).deviceChallenge(platform: 'android'), isNull);
      final junk = CapturingAdapter({'challengeId': 'c', 'challenge': '%%%'});
      expect(await apiWith(junk).deviceChallenge(platform: 'android'), isNull);
      expect(junk.requests.single.data, {'platform': 'android'});
    });
  });

  test('config and workflow resolution carry the Play Integrity project', () {
    final block = {
      'deviceAttestation': {'playIntegrityCloudProjectNumber': '424242'}
    };
    expect(SdkConfigResponse.fromJson(block).playIntegrityCloudProjectNumber,
        '424242');
    expect(WorkflowResolution.fromJson(block).playIntegrityCloudProjectNumber,
        '424242');
    expect(
        playIntegrityProjectOf({
          'deviceAttestation': {'playIntegrityCloudProjectNumber': 7}
        }),
        '7');
    expect(
        playIntegrityProjectOf({
          'deviceAttestation': {'playIntegrityCloudProjectNumber': null}
        }),
        isNull);
    expect(SdkConfigResponse.fromJson(const {}).playIntegrityCloudProjectNumber,
        isNull);
  });
}
