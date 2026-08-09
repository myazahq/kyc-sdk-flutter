import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/contact_verification.dart';

// Which channels a phone OTP step offers, and which one is used until the user
// picks. Worth testing on its own because every failure here is silent: a wrong
// default sends every code down a channel the org did not choose, and the user
// simply sees a code that never arrives.

PhoneVerificationConfig cfg(List<String> channels) =>
    PhoneVerificationConfig(enabled: true, channels: channels);

void main() {
  group('offeredChannels', () {
    test('falls back to SMS, matching the server default for an omitted via',
        () {
      expect(cfg(const []).offeredChannels, ['sms']);
      // The constructor default is already sms; assert it stays that way.
      expect(const PhoneVerificationConfig().offeredChannels, ['sms']);
    });

    test('keeps the workflow order, so the first entry is the default', () {
      expect(cfg(const ['whatsapp', 'sms']).offeredChannels,
          ['whatsapp', 'sms']);
      expect(cfg(const ['whatsapp', 'sms']).via, 'whatsapp');
    });

    test('drops channels this build cannot render', () {
      // A channel added server-side must not surface as an unlabelled button
      // in an app built before it existed.
      expect(cfg(const ['sms', 'telegram']).offeredChannels, ['sms']);
      expect(cfg(const ['telegram']).offeredChannels, ['sms']);
    });

    test('collapses duplicates', () {
      expect(cfg(const ['sms', 'sms', 'whatsapp']).offeredChannels,
          ['sms', 'whatsapp']);
    });

    test('via is always one of the offered channels', () {
      for (final input in [
        const <String>[],
        const ['telegram'],
        const ['whatsapp'],
        const ['sms', 'whatsapp'],
      ]) {
        final c = cfg(input);
        expect(c.offeredChannels, contains(c.via));
      }
    });
  });

  group('fromJson', () {
    test('reads the offered channels a workflow published', () {
      final parsed = PhoneVerificationConfig.fromJson({
        'enabled': true,
        'channels': ['sms', 'whatsapp'],
      });
      expect(parsed.offeredChannels, ['sms', 'whatsapp']);
    });

    test('an absent channels list still resolves to SMS', () {
      final parsed = PhoneVerificationConfig.fromJson({'enabled': true});
      expect(parsed.offeredChannels, ['sms']);
    });
  });
}
