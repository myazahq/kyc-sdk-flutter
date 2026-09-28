import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_collection.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/background_presence.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_auto_report.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_reporter.dart';

// ─── The SDK reports presence itself ─────────────────────────────────────────
//
// Production, 2026-09-28: every live watch sat at 0 days / 0 nights because
// observations only ever came from calls the host app had to add, and most
// companies had not. The SDK now arms background monitoring (on by default)
// and makes the first report on submit. A port of the RN SDK's
// presenceAutoReport.test.ts — keep them in lockstep.

MyazaKYCConfig _config({String? userId, bool presence = true, bool background = true, String? devUrl}) =>
    MyazaKYCConfig(
      apiKey: 'pk_dev_x',
      devUrl: devUrl,
      userId: userId,
      addressCollection: AddressCollectionConfig(presenceEnabled: presence, presenceBackground: background),
    );

const _reported = PresenceReportResult(true, true, PresenceReportReason.reported);
const _armed = EnableBackgroundResult(true, BackgroundPresenceReason.started);

void main() {
  group('shouldAutoReportPresence', () {
    test('acts when the flow ran presence and carries a user reference', () {
      expect(shouldAutoReportPresence(_config(userId: 'user_42')), isTrue);
    });

    test('stays quiet when presence is off or absent', () {
      expect(shouldAutoReportPresence(_config(userId: 'user_42', presence: false)), isFalse);
      expect(shouldAutoReportPresence(const MyazaKYCConfig(apiKey: 'pk_dev_x', userId: 'user_42')), isFalse);
    });

    test('stays quiet without a user reference (no pin was stored under one)', () {
      expect(shouldAutoReportPresence(_config()), isFalse);
      expect(shouldAutoReportPresence(_config(userId: '  ')), isFalse);
    });
  });

  group('background monitoring default', () {
    test('a workflow that does not mention it gets it on', () {
      final parsed = AddressCollectionConfig.fromJson({
        'enabled': true,
        'presence': {'enabled': true},
      });
      expect(parsed.presenceBackground, isTrue);
      expect(
        AddressCollectionConfig.fromJson({
          'presence': {'enabled': true, 'background': false},
        }).presenceBackground,
        isFalse,
      );
    });

    test('wantsBackgroundPresence follows the workflow', () {
      expect(wantsBackgroundPresence(_config(userId: 'user_42')), isTrue);
      expect(wantsBackgroundPresence(_config(userId: 'user_42', background: false)), isFalse);
    });
  });

  group('autoReportPresence', () {
    test('arms background monitoring first, then reports, with the flow key and user reference', () async {
      final calls = <String>[];
      final outcome = await autoReportPresence(
        _config(userId: 'user_42', devUrl: 'http://10.0.2.2:3001'),
        enableBackground: ({required apiKey, required externalUserId, devUrl}) async {
          calls.add('background $apiKey $externalUserId $devUrl');
          return _armed;
        },
        report: ({required apiKey, required externalUserId, devUrl}) async {
          calls.add('report $apiKey $externalUserId $devUrl');
          return _reported;
        },
      );
      expect(calls, [
        'background pk_dev_x user_42 http://10.0.2.2:3001',
        'report pk_dev_x user_42 http://10.0.2.2:3001',
      ]);
      expect(outcome?.background?.started, isTrue);
      expect(outcome?.report?.reason, PresenceReportReason.reported);
    });

    test('only reports when the workflow turns background monitoring off', () async {
      var armed = false;
      await autoReportPresence(
        _config(userId: 'user_42', background: false),
        enableBackground: ({required apiKey, required externalUserId, devUrl}) async {
          armed = true;
          return _armed;
        },
        report: ({required apiKey, required externalUserId, devUrl}) async => _reported,
      );
      expect(armed, isFalse);
    });

    test('does nothing when it should not act', () async {
      var called = false;
      final outcome = await autoReportPresence(
        _config(userId: 'user_42', presence: false),
        enableBackground: ({required apiKey, required externalUserId, devUrl}) async {
          called = true;
          return _armed;
        },
        report: ({required apiKey, required externalUserId, devUrl}) async {
          called = true;
          return _reported;
        },
      );
      expect(outcome, isNull);
      expect(called, isFalse);
    });

    test('never throws, and still reports when arming fails', () async {
      final outcome = await autoReportPresence(
        _config(userId: 'user_42'),
        enableBackground: ({required apiKey, required externalUserId, devUrl}) async => throw Exception('boom'),
        report: ({required apiKey, required externalUserId, devUrl}) async => _reported,
      );
      expect(outcome?.background, isNull);
      expect(outcome?.report?.reason, PresenceReportReason.reported);
    });
  });
}
