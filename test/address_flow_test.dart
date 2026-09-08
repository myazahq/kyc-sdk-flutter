import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart' show MapLatLng;
import 'package:myaza_kyc_sdk_flutter/src/utils/step_log.dart';

// ─── The address flow's pure rules ───────────────────────────────────────────
//
// A port of the web SDK's steps/address/flow-steps.test.ts, case for case. The
// numbers here are cross-SDK mirrors: if one of these fails after a change,
// the change has to land on web and React Native too, or one platform will
// strand an applicant the others do not.

AddressFlowOptions _options({
  bool searchAvailable = false,
  String photoMode = 'off',
  bool streetViewOffered = false,
}) =>
    AddressFlowOptions(
      searchAvailable: searchAvailable,
      photoMode: photoMode,
      streetViewOffered: streetViewOffered,
    );

const _picked = AddressState(
  lat: 4.9323964,
  lng: 8.3254216,
  label: '11 Bassey Street, Idim Ita, Calabar',
  pickedAt: AddressPickedAt(4.9323964, 8.3254216),
);

void main() {
  group('addressFlowSteps', () {
    test('is pin + review at minimum', () {
      expect(addressFlowSteps(_options()),
          [KYCStep.addressCollection, KYCStep.addressReview]);
    });

    test('adds search when a backend is available', () {
      expect(addressFlowSteps(_options(searchAvailable: true)).first,
          KYCStep.addressSearch);
    });

    test('adds the entrance step for a photo mode OR street view', () {
      expect(addressFlowSteps(_options(photoMode: 'optional')),
          contains(KYCStep.addressEntrance));
      expect(addressFlowSteps(_options(streetViewOffered: true)),
          contains(KYCStep.addressEntrance));
    });

    test('walks forward and back within the flow, null at the edges', () {
      final steps = addressFlowSteps(_options(
        searchAvailable: true,
        photoMode: 'optional',
        streetViewOffered: true,
      ));
      expect(nextAddressStep(steps, KYCStep.addressSearch),
          KYCStep.addressCollection);
      expect(nextAddressStep(steps, KYCStep.addressReview), isNull);
      expect(prevAddressStep(steps, KYCStep.addressCollection),
          KYCStep.addressSearch);
      expect(prevAddressStep(steps, KYCStep.addressSearch), isNull);
    });

    test('the four steps carry the shared wire names', () {
      expect(kStepWireNames[KYCStep.addressSearch], 'address-search');
      expect(kStepWireNames[KYCStep.addressCollection], 'address-collection');
      expect(kStepWireNames[KYCStep.addressEntrance], 'address-entrance');
      expect(kStepWireNames[KYCStep.addressReview], 'address-review');
    });
  });

  group('addressFlowOptions', () {
    test('photo defaults to optional, and preview hides the search step', () {
      final offered = addressFlowOptions(
          serverSearch: true, previewMode: false, hasGoogleKey: false, hasStreetViewFrame: false);
      expect(offered.photoMode, 'optional');
      expect(offered.searchAvailable, isTrue);

      final preview = addressFlowOptions(
          serverSearch: true, previewMode: true, hasGoogleKey: false, hasStreetViewFrame: false);
      expect(preview.searchAvailable, isFalse);
    });

    test('street view needs the key as well as the workflow', () {
      expect(
        addressFlowOptions(
                serverSearch: false, previewMode: false, hasGoogleKey: true, hasStreetViewFrame: false)
            .streetViewOffered,
        isTrue,
      );
      // What a mobile mount always resolves to: no browser surface, no framing.
      expect(
        addressFlowOptions(
                serverSearch: false, previewMode: false, hasGoogleKey: false, hasStreetViewFrame: false)
            .streetViewOffered,
        isFalse,
      );
      expect(
        addressFlowOptions(
          streetView: 'off',
          serverSearch: false,
          previewMode: false,
          hasGoogleKey: true, hasStreetViewFrame: false,
        ).streetViewOffered,
        isFalse,
      );
    });
  });

  group('metersBetween', () {
    test('measures a small nudge in metres', () {
      // ~111m per 0.001 degrees of latitude.
      final d = metersBetween(
          const MapLatLng(4.932, 8.325), const MapLatLng(4.933, 8.325));
      expect(d, greaterThan(100));
      expect(d, lessThan(125));
    });

    test('a same-compound nudge stays inside the keep radius; a district hop '
        'does not', () {
      const pick = MapLatLng(4.9323964, 8.3254216);
      const nudge = MapLatLng(4.9331, 8.326); // ~110m
      const far = MapLatLng(4.95, 8.34); // ~2.5km
      expect(metersBetween(pick, nudge),
          lessThanOrEqualTo(kKeepPickedLabelRadiusM));
      expect(metersBetween(pick, far), greaterThan(kKeepPickedLabelRadiusM));
    });
  });

  group('shouldAskLabelDecision', () {
    test('stays silent while the move is roof-refinement', () {
      // ~11m nudge: keep the picked label without asking.
      expect(shouldAskLabelDecision(_picked.copyWith(lat: _picked.lat + 0.0001)),
          isFalse);
    });

    test('asks once the pin has genuinely moved', () {
      expect(shouldAskLabelDecision(_picked.copyWith(lat: _picked.lat + 0.0005)),
          isTrue);
    });

    test('respects an answered "keep"', () {
      expect(
        shouldAskLabelDecision(
            _picked.copyWith(lat: _picked.lat + 0.0005, labelKept: true)),
        isFalse,
      );
    });

    test('never asks about a derived label', () {
      // No pickedAt anchor: reverse-geocoded labels re-derive freely instead.
      const derived = AddressState(
        lat: 4.9328964,
        lng: 8.3254216,
        label: '11 Bassey Street, Idim Ita, Calabar',
      );
      expect(shouldAskLabelDecision(derived), isFalse);
    });
  });

  group('addressVendorsStubbed', () {
    test('SANDBOX stubs the vendors; DEVELOPMENT and PRODUCTION do not', () {
      expect(addressVendorsStubbed(environment: 'SANDBOX'), isTrue);
      // The dev-is-real rule: a development key exercises the real surfaces.
      expect(addressVendorsStubbed(environment: 'DEVELOPMENT'), isFalse);
      expect(addressVendorsStubbed(environment: 'PRODUCTION'), isFalse);
      // An unknown or absent environment counts as live: a stub is only ever
      // reached on positive evidence that this is a test key.
      expect(addressVendorsStubbed(environment: null), isFalse);
      expect(addressVendorsStubbed(environment: 'staging'), isFalse);
    });

    test('a stubbed mount drops the search step', () {
      // The caller ANDs the flag into serverSearch (the RN wrapper's shape),
      // because a search box nothing can answer is worse than no step.
      final stubbed = addressFlowOptions(
        serverSearch: true && !addressVendorsStubbed(environment: 'SANDBOX'),
        previewMode: false,
        hasGoogleKey: false, hasStreetViewFrame: false,
      );
      expect(stubbed.searchAvailable, isFalse);
      expect(addressFlowSteps(stubbed), isNot(contains(KYCStep.addressSearch)));

      final live = addressFlowOptions(
        serverSearch: true && !addressVendorsStubbed(environment: 'DEVELOPMENT'),
        previewMode: false,
        hasGoogleKey: false, hasStreetViewFrame: false,
      );
      expect(live.searchAvailable, isTrue);
      expect(addressFlowSteps(live), contains(KYCStep.addressSearch));
    });
  });


  group('the framed street view offers the entrance step on mobile', () {
    AddressFlowOptions options({String streetView = 'optional', required bool frame}) =>
        addressFlowOptions(
          streetView: streetView,
          serverSearch: true,
          previewMode: false,
          hasGoogleKey: false,
          hasStreetViewFrame: frame,
        );

    test('is offered when the server minted a maps frame for this mount', () {
      expect(options(frame: true).streetViewOffered, isTrue);
      expect(options(frame: false).streetViewOffered, isFalse);
    });

    test('is never offered when the workflow opted out', () {
      expect(options(streetView: 'off', frame: true).streetViewOffered, isFalse);
    });

    test('is offered for a required step too, with the photo still the fallback', () {
      expect(options(streetView: 'required', frame: true).streetViewOffered, isTrue);
    });
  });
}
