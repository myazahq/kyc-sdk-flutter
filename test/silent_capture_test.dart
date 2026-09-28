import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/silent_capture.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/silent_capture_session.dart';

// ─── Silent capture: the pure rules, and one verification's session ─────────
//
// The same rules as the web and React Native SDKs: an absent flag is on, only
// document capture takes frames, so no scoped flow does, at most three per
// verification, and slots are 1-based in capture order with no gaps.

SilentCaptureFrame _frame(int order, {String? id, String moment = 'document'}) => SilentCaptureFrame(
      mediaId: id ?? 'med_$order',
      moment: moment,
      capturedAt: DateTime.utc(2026, 9, 28, 10, 0, order),
      order: order,
    );

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

void main() {
  group('silentCaptureApplies', () {
    test('an absent flag is on; only false turns it off', () {
      expect(silentCaptureApplies(flag: null, scope: null), isTrue);
      expect(silentCaptureApplies(flag: true, scope: null), isTrue);
      expect(silentCaptureApplies(flag: false, scope: null), isFalse);
    });

    test('no scoped flow takes frames: none of them captures a document', () {
      for (final scope in ['biometric-authentication', 'biometric-enrollment', 'address', 'questionnaire', 'contact']) {
        expect(silentCaptureApplies(flag: null, scope: scope), isFalse, reason: scope);
      }
      // An unknown scope is the full flow, as everywhere else in the SDK.
      expect(silentCaptureApplies(flag: null, scope: 'something-new'), isTrue);
    });
  });

  group('SilentCaptureLedger', () {
    test('caps at three, counting frames still uploading', () {
      var ledger = const SilentCaptureLedger();
      final orders = <int>[];
      for (var i = 0; i < 5; i++) {
        final claim = ledger.reserve();
        if (claim == null) break;
        ledger = claim.$1;
        orders.add(claim.$2);
      }
      expect(orders, [1, 2, 3]);
      expect(ledger.canTake, isFalse);
    });

    test('a released claim frees its place without reusing its order', () {
      var ledger = const SilentCaptureLedger();
      ledger = ledger.reserve()!.$1; // order 1, fails
      ledger = ledger.release();
      final claim = ledger.reserve()!;
      expect(claim.$2, 2);
    });

    test('records never exceed the cap or duplicate an order', () {
      var ledger = const SilentCaptureLedger();
      ledger = ledger.record(_frame(1)).record(_frame(1)).record(_frame(2));
      ledger = ledger.record(_frame(3)).record(_frame(4));
      expect(ledger.frames.map((f) => f.order), [1, 2, 3]);
    });
  });

  group('submission shape', () {
    test('slots are 1-based in capture order with no gaps', () {
      // Order 2 failed to upload; 3 arrived before 1.
      final frames = [_frame(3), _frame(1)];
      expect(silentCaptureMediaIds(frames), {
        'silentCapture1': 'med_1',
        'silentCapture2': 'med_3',
      });
      expect(silentCaptureDeviceEntries(frames), [
        {'slot': 1, 'moment': 'document', 'capturedAt': '2026-09-28T10:00:01.000Z'},
        {'slot': 2, 'moment': 'document', 'capturedAt': '2026-09-28T10:00:03.000Z'},
      ]);
    });

    test('the device block is untouched when nothing was uploaded', () {
      final device = {'os': 'ios'};
      expect(withSilentCaptureDevice(device, const []), same(device));
      expect(withSilentCaptureDevice(null, const []), isNull);
      final withFrames = withSilentCaptureDevice(device, [_frame(1)])!;
      expect(withFrames['os'], 'ios');
      expect((withFrames['silentCapture'] as List).single['slot'], 1);
    });
  });

  group('SilentCaptureSession', () {
    test('uploads in the background and keeps only accepted frames', () async {
      final session = SilentCaptureSession();
      final uploads = <Completer<String>>[];
      Future<String> upload(Uint8List _) {
        final c = Completer<String>();
        uploads.add(c);
        return c.future;
      }

      for (var i = 0; i < 4; i++) {
        await session.capture(grab: () async => _jpeg, upload: upload, moment: 'document');
      }
      // The fourth never grabbed: three places were already claimed.
      expect(uploads, hasLength(3));
      uploads[0].complete('a');
      uploads[1].completeError(Exception('offline'));
      uploads[2].complete('c');
      await Future<void>.delayed(Duration.zero);
      expect(session.frames.map((f) => f.mediaId), ['a', 'c']);
      expect(silentCaptureMediaIds(session.frames), {'silentCapture1': 'a', 'silentCapture2': 'c'});
      // The failed upload freed a place, so a retake may fill it.
      expect(session.canTake, isTrue);
    });

    test('a frame that cannot be grabbed claims nothing', () async {
      final session = SilentCaptureSession();
      final grabbed = await session.capture(
        grab: () async => null,
        upload: (_) async => 'x',
        moment: 'document',
      );
      expect(grabbed, isFalse);
      for (var i = 0; i < 3; i++) {
        expect(
          await session.capture(grab: () async => _jpeg, upload: (_) async => 'm$i', moment: 'document'),
          isTrue,
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(session.frames, hasLength(3));
    });

    test('an upload landing after a reset is not filed', () async {
      final session = SilentCaptureSession();
      final pending = Completer<String>();
      await session.capture(grab: () async => _jpeg, upload: (_) => pending.future, moment: 'document');
      session.reset();
      pending.complete('late');
      await Future<void>.delayed(Duration.zero);
      expect(session.frames, isEmpty);
    });
  });
}
