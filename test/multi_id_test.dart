import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/multi_id.dart';

// These rules MIRROR the server's lib/multi-id.ts. The server validates the
// pick sequence the client produced, so a client that computes options
// differently produces submissions the server rejects.

void main() {
  group('MultiIdConfig.fromJson', () {
    test('reads the policy', () {
      final cfg = MultiIdConfig.fromJson({'count': 2, 'minPassed': 2});
      expect(cfg!.count, 2);
      expect(cfg.minPassed, 2);
    });

    test('REJECTS an out-of-range count rather than clamping it', () {
      // The server returns null here. Clamping would walk 3 checks for a config
      // the server does not consider multi-ID at all.
      expect(MultiIdConfig.fromJson({'count': 9, 'minPassed': 9}), isNull);
      expect(MultiIdConfig.fromJson({'count': 1, 'minPassed': 1}), isNull);
      expect(MultiIdConfig.fromJson(null), isNull);
    });

    test('clamps minPassed within the count', () {
      expect(MultiIdConfig.fromJson({'count': 2, 'minPassed': 5})!.minPassed, 2);
      expect(MultiIdConfig.fromJson({'count': 2, 'minPassed': 0})!.minPassed, 1);
      // Absent ⇒ all must pass, the strict reading.
      expect(MultiIdConfig.fromJson({'count': 3})!.minPassed, 3);
    });
  });

  group('safe options', () {
    const offered = ['nin', 'bvn', 'passport'];

    test('never offers an ID already used earlier in the run', () {
      final options = multiIdSlotOptions(2, null, offered);
      expect(multiIdSafeOptions(options, 1, ['nin']), ['bvn', 'passport']);
    });

    test('never offers a pick that would STRAND a later check', () {
      // Check 2 may only offer BVN. Picking BVN first would leave it nothing.
      final options = multiIdSlotOptions(2, [null, ['bvn']], offered);
      expect(multiIdSafeOptions(options, 0, const []), ['nin', 'passport']);
    });

    test('offers nothing when every remaining pick would strand', () {
      final options = multiIdSlotOptions(2, [['bvn'], ['bvn']], offered);
      expect(multiIdSafeOptions(options, 0, const []), isEmpty);
    });

    test('a pinned check is narrowed to what the country actually offers', () {
      final options = multiIdSlotOptions(2, [['nin', 'nowhere'], null], offered);
      expect(options[0], ['nin']);
    });
  });

  group('MultiIdSlot.toWire', () {
    test('strips the local capture paths kept for the back journey', () {
      // A device file path must never reach the submission.
      const slot = MultiIdSlot(
        idType: 'nin',
        idNumber: '123',
        documentFront: 'med_1',
        documentFrontVideo: 'med_2',
        documentFrontPath: '/data/user/0/tmp/front.jpg',
      );
      expect(slot.toWire(), {
        'idType': 'nin',
        'idNumber': '123',
        'documentFront': 'med_1',
        // Each check's OWN recording rides its check, not the row's single
        // documentFrontVideo column.
        'documentFrontVideo': 'med_2',
      });
    });
  });
}
