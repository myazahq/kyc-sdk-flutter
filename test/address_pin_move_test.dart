import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_collection.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_pin_move.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';

// ─── What a pin move, or a pick, means ───────────────────────────────────────
//
// The rules the pin screen rests on, tested without a map or a network call.
// Mirrors the web SDK's use-pin-actions.ts behaviour; a drift here means one
// platform silently discards an address the other keeps.

AddressState _picked({
  double lat = 6.4281,
  double lng = 3.4219,
  String label = '11 Bassey Street, Idim Ita, Calabar',
  bool labelKept = false,
}) =>
    AddressState(
      lat: lat,
      lng: lng,
      label: label,
      labelKept: labelKept,
      pickedAt: const AddressPickedAt(6.4281, 3.4219),
    );

void main() {
  group('resolvePinMove', () {
    test('ignores a settle inside the epsilon on BOTH axes', () {
      final move = resolvePinMove(
        const AddressState(lat: 6.4281, lng: 3.4219),
        const MapLatLng(6.428101, 3.421901),
      );
      // A tile roundtrip drifting is not a move. Acting on it rebuilt the
      // address without its label and let the geocoder overwrite a pick.
      expect(move.address, isNull);
      expect(move.relabel, isFalse);
    });

    test('a move outside the epsilon on ONE axis still counts', () {
      final move = resolvePinMove(
        const AddressState(lat: 6.4281, lng: 3.4219),
        const MapLatLng(6.4281, 3.4300),
      );
      expect(move.address, isNotNull);
      expect(move.relabel, isTrue);
    });

    test('a PICKED label survives a nudge, and is not re-derived', () {
      final move = resolvePinMove(_picked(), const MapLatLng(6.4285, 3.4222));
      expect(move.address!.label, '11 Bassey Street, Idim Ita, Calabar');
      expect(move.address!.pickedAt, isNotNull);
      expect(move.relabel, isFalse);
    });

    test('a nudge inside the credibility radius leaves an answered keep', () {
      // ~50m: past the prompt threshold, nowhere near the 250m radius.
      final move =
          resolvePinMove(_picked(labelKept: true), const MapLatLng(6.4285, 3.4222));
      expect(move.address!.labelKept, isTrue);
    });

    test('crossing the credibility radius re-opens an answered keep', () {
      // ~1.1km away: the pick no longer credibly names the spot, so the
      // question is asked again — exactly once, out there.
      final move =
          resolvePinMove(_picked(labelKept: true), const MapLatLng(6.4381, 3.4219));
      expect(move.address!.labelKept, isFalse);
      expect(move.address!.label, isNotNull, reason: 'never silently dropped');
    });

    test('a DERIVED label dies with the spot it described', () {
      final move = resolvePinMove(
        const AddressState(
            lat: 6.4281, lng: 3.4219, label: 'Idim Ita, Calabar'),
        const MapLatLng(6.4300, 3.4300),
      );
      expect(move.address!.label, isNull);
      expect(move.relabel, isTrue);
    });

    test('typed fields and a captured frame survive a rebuild', () {
      final move = resolvePinMove(
        const AddressState(
          lat: 6.4281,
          lng: 3.4219,
          propertyNumber: '8',
          directions: 'black gate',
          street: 'Wisdom Close',
          streetView: AddressStreetView(
              panoId: 'p1', heading: 10, pitch: 0, fov: 90),
        ),
        const MapLatLng(6.4300, 3.4300),
      );
      expect(move.address!.propertyNumber, '8');
      expect(move.address!.directions, 'black gate');
      expect(move.address!.street, 'Wisdom Close');
      expect(move.address!.streetView?.panoId, 'p1');
    });

    test('a dragged pin drops the GPS accuracy it no longer has', () {
      // Both branches: the accuracy described a measurement, and a drag is not
      // one, so carrying the figure forward would submit a false claim.
      final rebuilt = resolvePinMove(
        const AddressState(lat: 6.4281, lng: 3.4219, accuracy: 12),
        const MapLatLng(6.4300, 3.4300),
      );
      expect(rebuilt.address!.accuracy, isNull);

      final kept = resolvePinMove(
        _picked().copyWith(accuracy: 12),
        const MapLatLng(6.4285, 3.4222),
      );
      expect(kept.address!.accuracy, isNull);
    });
  });
}
