import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';

// ─── Address-only flows (Address Intelligence standalone) ────────────────────
//
// No identity step at all: consent → (contact) → (PoA) → the address flow →
// (questionnaire) → submitted, submitted with idType 'address'. Built for
// books whose identity verification already happened elsewhere. Mirrors the
// web and RN SDKs' address-only step-order tests.

MyazaKYCConfig _config({bool poa = false}) => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      scope: 'address',
      addressCollection: const AddressCollectionConfig(enabled: true),
      proofOfAddress: poa ? const ProofOfAddressConfig(enabled: true) : null,
    );

void main() {
  test('the flow has no identity steps at all', () {
    final order = buildStepOrder(_config(), const KYCState());
    expect(order.first, KYCStep.consent);
    expect(order.last, KYCStep.submitted);
    for (final step in [
      KYCStep.idType,
      KYCStep.idInput,
      KYCStep.documentCapture,
      KYCStep.liveness,
      KYCStep.nfc,
      KYCStep.countrySelect,
    ]) {
      expect(order, isNot(contains(step)));
    }
    expect(order, contains(KYCStep.addressCollection));
  });

  test('the identity-free companions keep their usual order', () {
    final order = buildStepOrder(_config(poa: true), const KYCState());
    final poaIndex = order.indexOf(KYCStep.proofOfAddress);
    final addressIndex = order.indexOf(KYCStep.addressCollection);
    expect(poaIndex, greaterThan(-1));
    expect(addressIndex, greaterThan(poaIndex));
  });
}
