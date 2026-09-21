import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/country_id_types.dart';

// ─── Which ID types a country offers ──────────────────────────────────────────
//
// Regression (user report 2026-09-21): on the Flutter SDK every other workflow
// change reached the app, but the ID types never did — the picker kept offering
// every granted ID no matter what the builder published.
//
// Cause: the per-country filter ignored a `countries` list of length 1, and
// publish MATERIALISES the selection into exactly that shape:
//   { "country": "NG", "idTypes": ["nin","tax-id","passport"] }   (one entry)
//   "idTypes": null                                               (top level)
// so a single-country flow's selection was read as "unset" = all granted.

void main() {
  group('pinnedIdTypesFor', () {
    // The published shape of the reported workflow (wf__uT_Z0JWpANb v3).
    const singleCountry = MyazaKYCConfig(
      apiKey: 'pk_test_x',
      country: 'NG',
      countries: [
        WorkflowCountryOption(
          country: 'NG',
          idTypes: ['nin', 'tax-id', 'passport'],
        ),
      ],
    );

    test('a SINGLE-entry countries list still narrows the picker', () {
      expect(
        pinnedIdTypesFor(singleCountry, 'NG'),
        ['nin', 'tax-id', 'passport'],
      );
    });

    test('a multi-region flow narrows to the PICKED country', () {
      const multi = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        countries: [
          WorkflowCountryOption(country: 'NG', idTypes: ['bvn']),
          WorkflowCountryOption(country: 'GH', idTypes: ['ghana-card']),
        ],
      );
      expect(pinnedIdTypesFor(multi, 'NG'), ['bvn']);
      expect(pinnedIdTypesFor(multi, 'GH'), ['ghana-card']);
    });

    test('country match is case-insensitive', () {
      expect(pinnedIdTypesFor(singleCountry, 'ng'), isNotNull);
    });

    test('an EMPTY per-country list means all granted, not none', () {
      const emptyPin = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        countries: [WorkflowCountryOption(country: 'NG', idTypes: [])],
      );
      expect(pinnedIdTypesFor(emptyPin, 'NG'), isNull);
    });

    test('an empty per-country list falls through to the top-level list', () {
      const emptyPinWithTop = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        idTypes: ['bvn'],
        countries: [WorkflowCountryOption(country: 'NG', idTypes: [])],
      );
      expect(pinnedIdTypesFor(emptyPinWithTop, 'NG'), ['bvn']);
    });

    test('a country absent from the list falls back to the top level', () {
      const withTop = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        idTypes: ['bvn'],
        countries: [WorkflowCountryOption(country: 'GH', idTypes: ['ssnit'])],
      );
      expect(pinnedIdTypesFor(withTop, 'NG'), ['bvn']);
    });

    test('nothing pinned anywhere means every granted ID', () {
      const bare = MyazaKYCConfig(apiKey: 'pk_test_x', country: 'NG');
      expect(pinnedIdTypesFor(bare, 'NG'), isNull);
    });

    test('a prop-configured mount keeps its top-level idTypes', () {
      const propOnly = MyazaKYCConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        idTypes: ['bvn', 'nin'],
      );
      expect(pinnedIdTypesFor(propOnly, 'NG'), ['bvn', 'nin']);
    });
  });
}
