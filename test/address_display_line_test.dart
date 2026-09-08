import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';

// ─── The address line the flow SHOWS ─────────────────────────────────────────
//
// The client mirror of the server's composed-line rules, so what the applicant
// confirms on the pin summary and the review heading is what the org later
// reads. A port of the web SDK's displayAddressLine cases, case for case.
// Split from address_flow_test.dart (200-line rule), which keeps the flow
// shape and the label decision.

const _base = AddressState(lat: 4.9324, lng: 8.3254);

void main() {
  group('displayAddressLine', () {
    test('replaces a contradictory picked number with the typed one', () {
      expect(
        displayAddressLine(_base.copyWith(
            label: '11 Bassey Street, Idim Ita, Calabar', propertyNumber: '8')),
        '8 Bassey Street, Idim Ita, Calabar',
      );
    });

    test('never doubles a number the label already leads with', () {
      expect(
        displayAddressLine(_base.copyWith(
            label: '11 Bassey Street, Idim Ita', propertyNumber: '11')),
        '11 Bassey Street, Idim Ita',
      );
    });

    test('prefixes a number the label never carried', () {
      expect(
        displayAddressLine(_base.copyWith(
            label: 'Bassey Street, Calabar', propertyNumber: '8')),
        '8, Bassey Street, Calabar',
      );
    });

    test('leads with a typed street the label does not know', () {
      expect(
        displayAddressLine(_base.copyWith(
          label: 'Idim Ita, Calabar',
          propertyNumber: '8',
          street: 'Wisdom Close',
        )),
        '8 Wisdom Close, Idim Ita, Calabar',
      );
    });

    test('falls back to coordinates only when there is nothing typed either',
        () {
      expect(
        displayAddressLine(
            _base.copyWith(street: 'Wisdom Close', propertyNumber: '8')),
        '8 Wisdom Close',
      );
      // NEVER coordinates: an unlabelled pin has NO line, and the caller
      // shows that one is on its way.
      expect(displayAddressLine(_base), '');
    });
  });
}
