import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
// KYCEnvironment is internal (not exported from the barrel) — import the source
// for the detection tests.
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart' show KYCEnvironment;
import 'package:myaza_kyc_sdk_flutter/src/utils/resolve_url.dart';

void main() {
  // ── Validator smoke tests ────────────────────────────────────────────────────

  group('ID number validators', () {
    test('BVN accepts 11 digits', () {
      final result = validateIdNumber('12345678901', Country.NG, IdType.bvn);
      expect(result.isValid, isTrue);
    });

    test('BVN rejects short input', () {
      final result = validateIdNumber('1234', Country.NG, IdType.bvn);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('NIN accepts 11 digits', () {
      final result = validateIdNumber('12345678901', Country.NG, IdType.nin);
      expect(result.isValid, isTrue);
    });

    test('NG passport accepts A + 8 digits', () {
      final result =
          validateIdNumber('A12345678', Country.NG, IdType.passport);
      expect(result.isValid, isTrue);
    });

    test('NG passport rejects wrong format', () {
      final result =
          validateIdNumber('123456789', Country.NG, IdType.passport);
      expect(result.isValid, isFalse);
    });

    test('Ghana Card accepts GHA-XXXXXXXXX-Y', () {
      final result =
          validateIdNumber('GHA-123456789-0', Country.GH, IdType.ghanaCard);
      expect(result.isValid, isTrue);
    });

    test('SA National ID accepts 13 digits with valid DOB', () {
      final result =
          validateIdNumber('9001015009087', Country.ZA, IdType.nationalId);
      expect(result.isValid, isTrue);
    });

    test('SA National ID rejects invalid date of birth', () {
      // Month 13 is invalid
      final result =
          validateIdNumber('9013015009087', Country.ZA, IdType.nationalId);
      expect(result.isValid, isFalse);
    });
  });

  // ── ID masking ───────────────────────────────────────────────────────────────

  group('maskIdNumber', () {
    test('masks middle digits of an 11-digit ID', () {
      expect(maskIdNumber('12345678901'), '1234****901');
    });

    test('masks a short ID fully', () {
      expect(maskIdNumber('123'), '***');
    });
  });

  // ── Config defaults ──────────────────────────────────────────────────────────

  group('MyazaKYCConfig defaults', () {
    test('enableSelfie defaults to true', () {
      const config = MyazaKYCConfig(
        apiKey: 'key',
        country: Country.NG,
      );
      expect(config.enableSelfie, isTrue);
      expect(config.enableLiveness, isTrue);
      expect(config.enableDocumentCapture, isTrue);
    });
  });

  // ── Environment detection + base URL resolution ──────────────────────────────

  group('environment detection', () {
    test('derives the environment from the key prefix (pk_ and sk_)', () {
      expect(detectEnvironment('pk_dev_abc'), KYCEnvironment.development);
      expect(detectEnvironment('sk_dev_abc'), KYCEnvironment.development);
      expect(detectEnvironment('pk_test_abc'), KYCEnvironment.sandbox);
      expect(detectEnvironment('sk_test_abc'), KYCEnvironment.sandbox);
      expect(detectEnvironment('pk_live_abc'), KYCEnvironment.production);
      expect(detectEnvironment('sk_live_abc'), KYCEnvironment.production);
    });

    test('throws on an unrecognized / malformed key prefix', () {
      expect(() => detectEnvironment('nope_123'), throwsArgumentError);
      expect(() => detectEnvironment('pk_prod_123'), throwsArgumentError);
      expect(() => detectEnvironment('pklive_123'), throwsArgumentError);
      expect(() => detectEnvironment(''), throwsArgumentError);
    });
  });

  group('resolveBaseUrl', () {
    test('sandbox / production resolve to the canonical URLs', () {
      expect(resolveBaseUrl('pk_test_abc'), 'https://identity.myaza.app');
      expect(resolveBaseUrl('pk_live_abc'), 'https://identity.myaza.app');
    });

    test('devUrl is ignored for sandbox/production keys', () {
      expect(
        resolveBaseUrl('pk_live_abc', devUrl: 'http://localhost:9'),
        'https://identity.myaza.app',
      );
    });

    test('development keys honour devUrl when provided', () {
      expect(
        resolveBaseUrl('pk_dev_abc', devUrl: 'http://192.168.1.5:3001'),
        'http://192.168.1.5:3001',
      );
    });
  });
}
