import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_sdk_flutter/kyc_sdk_flutter.dart';
import 'package:kyc_sdk_flutter/src/utils/resolve_url.dart';

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

    test('environment defaults to production', () {
      const config = MyazaKYCConfig(apiKey: 'key', country: Country.NG);
      expect(config.environment, KYCEnvironment.production);
    });
  });

  // ── Base URL resolution ──────────────────────────────────────────────────────

  group('resolveBaseUrl', () {
    test('staging and production are hardcoded into the SDK', () {
      expect(resolveBaseUrl(KYCEnvironment.staging),
          'https://identity.myaza.app');
      expect(resolveBaseUrl(KYCEnvironment.production),
          'https://identity.myaza.app');
    });

    test('devUrl is ignored for staging/production', () {
      expect(
        resolveBaseUrl(KYCEnvironment.production, devUrl: 'http://localhost:9'),
        'https://identity.myaza.app',
      );
    });

    test('development honours devUrl when provided', () {
      expect(
        resolveBaseUrl(KYCEnvironment.development, devUrl: 'http://192.168.1.5:3001'),
        'http://192.168.1.5:3001',
      );
    });
  });
}
