import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/country_adoption.dart';

// ─── The shared vectors (test/country_adoption_vectors.json) ─────────────────
//
// One rule decides when a geocode or a picked address may change the declared
// country, on all three SDKs. The vectors are the one place it is written
// down as data; the web and RN mirrors run the same file. The second group
// pins this SDK's own wiring, since a decision nobody calls is no rule.

Map<String, dynamic> _vectors() => jsonDecode(
      File('test/country_adoption_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

List<String>? _list(dynamic v) =>
    v == null ? null : (v as List).cast<String>();

String read(String rel) => File('lib/src/$rel').readAsStringSync();

void main() {
  final data = _vectors();

  group('adoptionDecision (shared vectors)', () {
    for (final raw in data['adoption'] as List) {
      final v = raw as Map<String, dynamic>;
      final input = v['input'] as Map<String, dynamic>;
      test(v['name'] as String, () {
        final decision = adoptionDecision(
          country: input['country'] as String?,
          selectedCountry: input['selectedCountry'] as String?,
          countryAutoPicked: input['countryAutoPicked'] as bool,
          scope: input['scope'] as String?,
          accepted: _list(input['accepted']),
          explicit: input['explicit'] as bool,
        );
        final label = decision == null
            ? null
            : decision.auto
                ? 'set-auto'
                : 'set';
        expect(label, v['expect']);
        if (decision != null) {
          expect(decision.country, matches(RegExp(r'^[A-Z]{2}$')));
        }
      });
    }
  });

  group('geoDefaultCountry (shared vectors)', () {
    for (final raw in data['geoDefault'] as List) {
      final v = raw as Map<String, dynamic>;
      final input = v['input'] as Map<String, dynamic>;
      test(v['name'] as String, () {
        expect(
          geoDefaultCountry(
            geoCountry: input['geoCountry'] as String?,
            selectedCountry: input['selectedCountry'] as String?,
            scope: input['scope'] as String?,
            accepted: _list(input['accepted']),
          ),
          v['expect'],
        );
      });
    }
  });

  group('the flow runs the rule', () {
    test('every fix and reverse geocode hands its country to adoption', () {
      expect(read('screens/address/address_pin_label.dart'),
          contains('onGeocoded(result.parts?.country)'));
      final actions = read('screens/address/address_pin_actions.dart');
      expect('onGeocoded(f?.parts?.country)'.allMatches(actions).length, 3);
      expect(read('screens/address/address_flow_controller.dart'),
          contains('void onGeocoded(String? country) => adoptGeocodedCountry(country)'));
    });

    test('a picked address is explicit, and the address scope geo-defaults', () {
      expect(read('screens/address/address_search_step.dart'),
          contains('adoptGeocodedCountry(place.country, explicit: true)'));
      expect(read('screens/address/address_flow_controller.dart'),
          contains('scheduleGeoDefault()'));
    });

    test('the store flags a guessed country and a pick clears it', () {
      final provider = read('providers/kyc_provider.dart');
      expect(provider, contains('void setCountryAuto(String country)'));
      expect(provider, contains('countryAutoPicked: false,'));
    });

    test('the pin, hit and place all carry the geocoder\'s country', () {
      final api = read('services/api_address.dart');
      expect("country: _addressString(json['country'])".allMatches(api).length, 3);
      expect(read('screens/address/address_search_body.dart'),
          contains('country: hit.country'));
    });
  });
}
