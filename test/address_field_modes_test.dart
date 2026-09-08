import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_collection.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_field_modes.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart'
    show AddressParts;

// ─── Per-field address modes, replayed from the SHARED vector file ───────────
//
// The rule lives in three mirrors (web, RN, Flutter) and on the server; the
// vectors are the one place it is written down as data, so a drift in any
// mirror fails here rather than as a 422 on an applicant's last screen.

Map<String, dynamic> _vectors() => jsonDecode(
      File('test/address_field_modes_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

AddressCollectionConfig? _config(Object? raw) => raw is Map
    ? AddressCollectionConfig.fromJson(raw.cast<String, dynamic>())
    : null;

/// The base address with the vector's typed edits: a key present with ''
/// is a deliberate clear, an absent key was never touched.
AddressState _address(Map<String, dynamic> base, Map<String, dynamic> typed) {
  final parts = base['parts'] as Map<String, dynamic>;
  String? nullable(String key) =>
      typed.containsKey(key) ? typed[key] as String : null;
  return AddressState(
    lat: (base['lat'] as num).toDouble(),
    lng: (base['lng'] as num).toDouble(),
    propertyName: (typed['propertyName'] ?? base['propertyName']) as String,
    propertyNumber:
        (typed['propertyNumber'] ?? base['propertyNumber']) as String,
    street: nullable('street'),
    unit: nullable('unit'),
    neighbourhood: nullable('neighbourhood'),
    city: nullable('city'),
    state: nullable('state'),
    postcode: nullable('postcode'),
    parts: AddressParts.fromJson(parts),
  );
}

void main() {
  final data = _vectors();
  final base = data['address'] as Map<String, dynamic>;

  group('address field modes (shared vectors)', () {
    for (final raw in data['vectors'] as List) {
      final v = raw as Map<String, dynamic>;
      test(v['name'] as String, () {
        final config = _config(v['config']);
        final typed = (v['typed'] as Map).cast<String, dynamic>();
        final address = _address(base, typed);
        final modes = addressFieldModes(config);
        for (final entry in (v['expectModes'] as Map).entries) {
          expect(modes[entry.key]?.name, entry.value, reason: entry.key as String);
        }
        expect(missingRequiredAddressFields(config, address),
            (v['expectMissing'] as List).cast<String>());
        expect(requiredPrefillSubmission(config, address),
            (v['expectPrefill'] as Map).cast<String, String>());
      });
    }

    test('holds every key the server knows', () {
      expect(kAddressFieldKeys, [
        'propertyName',
        'propertyNumber',
        'street',
        'unit',
        'neighbourhood',
        'city',
        'state',
        'postcode',
      ]);
    });

    test('names the missing fields in the nudge, lower case, no em dash', () {
      final nudge = missingFieldsNudge(['propertyNumber', 'city']);
      expect(nudge, 'This flow needs: house or flat number, city.');
      expect(nudge.contains('—'), isFalse);
    });
  });

  group('addressPayload with the flow config', () {
    final address = _address(base, const {});
    final required =
        AddressCollectionConfig.fromJson(const {'fields': {'city': 'required'}});

    test('submits the displayed prefill of a required untouched field', () {
      final payload = addressPayload(address, config: required);
      expect(payload['city'], 'Calabar');
      expect(payload.containsKey('state'), isFalse);
    });

    test('lets a typed value win over the prefill', () {
      final payload = addressPayload(
        _address(base, const {'city': ' Uyo '}),
        config: required,
      );
      expect(payload['city'], 'Uyo');
    });

    test('adds nothing without a config and keeps the prefill ahead of the frame',
        () {
      expect(addressPayload(address).containsKey('city'), isFalse);
      final withFrame = addressPayload(
        address.copyWith(
          streetView: const AddressStreetView(
              panoId: 'p', heading: 1, pitch: 2, fov: 90),
        ),
        config: required,
      );
      final keys = withFrame.keys.toList();
      expect(keys.indexOf('city') < keys.indexOf('streetView'), isTrue);
    });

    test('session progress stays raw: no prefill is written as a claim', () {
      expect(addressProgressJson(address).containsKey('city'), isFalse);
    });
  });

  group('config parse', () {
    test('reads fields and drops wrong-typed entries', () {
      final cfg = AddressCollectionConfig.fromJson(const {
        'propertyFields': 'required',
        'fields': {'city': 'required', 'state': 3, 'unit': 'off'},
      });
      expect(cfg.propertyFields, 'required');
      expect(cfg.fields, {'city': 'required', 'unit': 'off'});
      expect(AddressCollectionConfig.fromJson(const {}).fields, isEmpty);
    });
  });
}
