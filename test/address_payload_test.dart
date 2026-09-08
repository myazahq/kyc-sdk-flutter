import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_state_json.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart'
    show AddressParts;

// ─── What leaves the address flow ────────────────────────────────────────────
//
// Two shapes, deliberately different sizes. The SUBMISSION carries only what
// the server acts on; the session SNAPSHOT carries the whole object, so a
// resume puts the applicant back where they were. Split from
// address_collection_test.dart (200-line rule), which keeps the config surface.

void main() {
  group('wire payload', () {
    test('carries only what was collected', () {
      expect(
        addressPayload(const AddressState(
            lat: 6.4281, lng: 3.4219, directions: '  ')),
        {'lat': 6.4281, 'lng': 3.4219},
      );
    });

    test('carries the attest fix when one was taken', () {
      expect(
        addressPayload(const AddressState(
          lat: 6.4281,
          lng: 3.4219,
          accuracy: 12,
          directions: 'black gate ',
          deviceLat: 6.4283,
          deviceLng: 3.4217,
          deviceAccuracy: 20,
          capturedAt: '2026-08-25T00:00:00.000Z',
        )),
        {
          'lat': 6.4281,
          'lng': 3.4219,
          'accuracy': 12,
          'directions': 'black gate',
          'deviceLat': 6.4283,
          'deviceLng': 3.4217,
          'deviceAccuracy': 20,
          'capturedAt': '2026-08-25T00:00:00.000Z',
        },
      );
    });

    test('carries the confirmed line, the typed street and a captured frame',
        () {
      final payload = addressPayload(const AddressState(
        lat: 6.4281,
        lng: 3.4219,
        label: ' 11 Bassey Street, Calabar ',
        street: ' Wisdom Close ',
        propertyNumber: ' 11 ',
        streetView: AddressStreetView(
          panoId: 'p1',
          heading: 90,
          pitch: 0,
          fov: 75,
        ),
      ));
      expect(payload['label'], '11 Bassey Street, Calabar');
      expect(payload['street'], 'Wisdom Close');
      expect(payload['propertyNumber'], '11');
      expect(payload['streetView'], {
        'panoId': 'p1',
        'heading': 90,
        'pitch': 0,
        'fov': 75,
      });
    });

    test('keeps the label reasoning off the wire, and the fix whole', () {
      // pickedAt and labelKept are how the CLIENT decides whether to ask the
      // applicant about a moved label. They are not facts about the address,
      // so the server never sees them; parts is display only for the same
      // reason. A device latitude without its longitude places nobody.
      final payload = addressPayload(const AddressState(
        lat: 6.4281,
        lng: 3.4219,
        label: '11 Bassey Street',
        pickedAt: AddressPickedAt(6.4281, 3.4219),
        labelKept: true,
        parts: AddressParts(city: 'Calabar'),
        deviceLat: 6.4283,
        capturedAt: '2026-08-25T00:00:00.000Z',
      ));
      expect(payload.containsKey('pickedAt'), isFalse);
      expect(payload.containsKey('labelKept'), isFalse);
      expect(payload.containsKey('parts'), isFalse);
      expect(payload.containsKey('deviceLat'), isFalse);
      expect(payload.containsKey('capturedAt'), isFalse);
    });

    test('the progress snapshot is richer than the wire', () {
      final progress = addressProgressJson(const AddressState(
        lat: 6.4281,
        lng: 3.4219,
        label: '11 Bassey Street',
        pickedAt: AddressPickedAt(6.4281, 3.4219),
        labelKept: true,
        parts: AddressParts(city: 'Calabar'),
      ));
      expect(progress['label'], '11 Bassey Street');
      expect(progress['pickedAt'], {'lat': 6.4281, 'lng': 3.4219});
      expect(progress['labelKept'], isTrue);
      expect((progress['parts'] as Map)['city'], 'Calabar');
    });
  });

  group('picked state', () {
    test('keeps what the applicant typed and prefills only an empty number',
        () {
      const prev = AddressState(
        lat: 1,
        lng: 1,
        directions: 'black gate',
        propertyNumber: '8',
        street: 'Wisdom Close',
        label: 'somewhere else',
        pickedAt: AddressPickedAt(1, 1),
      );
      final typed =
          AddressState.picked(prev, lat: 6.4281, lng: 3.4219, houseNumber: '11');
      expect(typed.propertyNumber, '8', reason: 'their word beats the map');
      expect(typed.directions, 'black gate');
      expect(typed.street, 'Wisdom Close');
      // The pick's own label is re-added by the caller, explicitly.
      expect(typed.label, isNull);
      expect(typed.pickedAt, isNull);

      final blank = AddressState.picked(
        const AddressState(lat: 1, lng: 1),
        lat: 6.4281,
        lng: 3.4219,
        houseNumber: '11',
      );
      expect(blank.propertyNumber, '11');
    });
  });
}
