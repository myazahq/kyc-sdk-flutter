import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/device_signals.dart';

import 'device_intel_fakes.dart';

// ─── Mobile fingerprint additions: stableId, integrity, attestation ──────────

void main() {
  group('DeviceSignals', () {
    test('collects stableId, normalised integrity and attestation', () async {
      final native = FakeNative()
        ..integrityOut = {
          'rooted': true,
          'hooked': 'yes',
          'signals': ['su_binary', 'made_up', 'su_binary', 'frida'],
        };
      final out = await DeviceSignals(native: native, platform: 'android')
          .collect(fetchChallenge: fetcher(), cloudProjectNumber: '9');
      expect(out['stableId'], 'stable-1');
      expect(out['integrity'], {
        'rooted': true,
        'hooked': null,
        'signals': ['su_binary', 'frida'],
      });
      expect(out['attestation'], isA<Map<String, dynamic>>());
    });

    test('an over-long stable id and a failed integrity read are omitted',
        () async {
      final native = FakeNative()
        ..stable = 'x' * 129
        ..integrityOut = null;
      final out = await DeviceSignals(native: native, platform: 'ios')
          .collect(fetchChallenge: fetcher(fail: true));
      expect(out, isEmpty);
    });

    test('not a phone: nothing at all', () async {
      final out = await DeviceSignals(native: FakeNative(), platform: null)
          .collect(fetchChallenge: fetcher());
      expect(out, isEmpty);
    });
  });
}
