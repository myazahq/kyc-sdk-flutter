import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_collection.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_pin_move.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_pin_summary.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── Adopting a searched address, and counting what was typed ────────────────
//
// A pick is the one moment a label becomes human-confirmed, so it anchors
// `pickedAt`; everything the applicant typed themselves outranks the map.
// Split from address_pin_move_test.dart (200-line rule), which keeps the
// rules for moving a pin that is already placed.

void main() {
  group('addressFromPick', () {
    test('anchors the label so it survives later nudges', () {
      final next = addressFromPick(
        null,
        const ResolvedPlace(
          lat: 6.5,
          lng: 3.4,
          houseNumber: '11',
          road: 'Bassey Street',
          formatted: '11 Bassey Street, Idim Ita',
          city: 'Calabar',
        ),
      );
      expect(next.label, '11 Bassey Street, Idim Ita');
      expect(next.pickedAt?.lat, 6.5);
      expect(next.parts?.city, 'Calabar');
      expect(next.propertyNumber, '11');
    });

    test('the applicant\'s typed number beats the map\'s', () {
      final next = addressFromPick(
        const AddressState(lat: 0, lng: 0, propertyNumber: '8'),
        const ResolvedPlace(lat: 6.5, lng: 3.4, houseNumber: '11'),
      );
      expect(next.propertyNumber, '8');
    });

    test('a resolved street retires the typed one back to null', () {
      final next = addressFromPick(
        const AddressState(lat: 0, lng: 0, street: 'Wisdom Close'),
        const ResolvedPlace(lat: 6.5, lng: 3.4, road: 'Bassey Street'),
      );
      // Null, never '': the details sheet reads '' as deliberately cleared,
      // which would suppress the resolved-street prefill it should show.
      expect(next.street, isNull);
    });

    test('a basic hit carries its line but no breakdown', () {
      final next = addressFromPick(
        null,
        const ResolvedPlace(
            lat: 6.5, lng: 3.4, formatted: 'Somewhere, Calabar'),
      );
      expect(next.label, 'Somewhere, Calabar');
      expect(next.parts, isNull);
    });

    test('a hit with no line leaves the label unanchored', () {
      // Without a line there is nothing for the applicant to have confirmed,
      // so the pin must not claim a human-confirmed label.
      final next =
          addressFromPick(null, const ResolvedPlace(lat: 6.5, lng: 3.4));
      expect(next.label, isNull);
      expect(next.pickedAt, isNull);
    });
  });

  group('addressDetailSummary', () {
    test('counts only what the applicant typed, and pluralises it', () {
      expect(addressDetailSummary(null),
          'A house number and directions help someone find it');
      expect(
          addressDetailSummary(
              const AddressState(lat: 0, lng: 0, propertyNumber: ' ')),
          'A house number and directions help someone find it');
      expect(
          addressDetailSummary(
              const AddressState(lat: 0, lng: 0, propertyNumber: '11')),
          '1 detail added');
      expect(
        addressDetailSummary(const AddressState(
            lat: 0,
            lng: 0,
            propertyNumber: '11',
            street: 'Wisdom Close',
            directions: 'black gate')),
        '3 details added',
      );
    });

    test('the map\'s own breakdown is not a detail the applicant added', () {
      expect(
        addressDetailSummary(const AddressState(
          lat: 0,
          lng: 0,
          label: '11 Bassey Street',
          parts: AddressParts(street: 'Bassey Street', city: 'Calabar'),
        )),
        'A house number and directions help someone find it',
      );
    });
  });
}
