import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_collection.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_flow.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart'
    show WorkflowFlowConfig;
import 'package:myaza_kyc_sdk_flutter/src/utils/step_log.dart';

// ─── Address Intelligence (smart-address capture) ────────────────────────────
//
// A map pin (+ optional door photo and directions) the server corroborates
// against the evidence it already holds. The result is SOFT — the client only
// collects; nothing here blocks beyond what the config explicitly requires.
// Mirrors the web and RN SDKs' addressCollection tests.

MyazaKYCConfig _config({
  AddressCollectionConfig? addressCollection,
  ProofOfAddressConfig? proofOfAddress,
  QuestionnaireConfig? questionnaire,
}) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      addressCollection: addressCollection,
      proofOfAddress: proofOfAddress,
      questionnaire: questionnaire,
    );

void main() {
  group('step presence', () {
    test('needs an explicit enable', () {
      expect(
          hasAddressCollectionStep(
              const AddressCollectionConfig(enabled: true)),
          isTrue);
      expect(hasAddressCollectionStep(const AddressCollectionConfig()),
          isFalse);
      expect(hasAddressCollectionStep(null), isFalse);
    });

    test('sits after Proof of Address, before the questionnaire', () {
      // The address capture is REAL steps, so the whole flow sits between the
      // two — contiguously, in order, with nothing else threaded through it.
      final order = buildStepOrder(
        _config(
          addressCollection: const AddressCollectionConfig(enabled: true),
          proofOfAddress: const ProofOfAddressConfig(enabled: true),
          questionnaire: QuestionnaireConfig.fromJson(const {
            'fields': [
              {'key': 'source_of_funds', 'label': 'Source of funds', 'type': 'text'},
            ],
          }),
        ),
        const KYCState(),
      );
      final poa = order.indexOf(KYCStep.proofOfAddress);
      final questionnaire = order.indexOf(KYCStep.questionnaire);
      expect(poa, greaterThan(-1));
      // No search step: the platform has not advertised a search backend.
      expect(order.sublist(poa + 1, questionnaire), [
        KYCStep.addressCollection,
        KYCStep.addressEntrance,
        KYCStep.addressReview,
      ]);
    });

    test('offers the search step only when the platform serves one', () {
      List<KYCStep> orderWith({required bool search}) => buildStepOrder(
            _config(
                addressCollection:
                    const AddressCollectionConfig(enabled: true)),
            KYCState(
              serverConfig: ServerSdkConfig(
                status: ServerConfigStatus.ready,
                addressSearch: search,
                addressSearchMode: search ? 'basic' : null,
              ),
            ),
          );
      expect(orderWith(search: true).contains(KYCStep.addressSearch), isTrue);
      // Without a backend the applicant still places the pin by hand, which is
      // what every failure path degrades to anyway.
      expect(orderWith(search: false).contains(KYCStep.addressSearch), isFalse);
    });

    test('drops the entrance step when the photo slot is off', () {
      final order = buildStepOrder(
        _config(
            addressCollection:
                const AddressCollectionConfig(enabled: true, photo: 'off')),
        const KYCState(),
      );
      expect(order.contains(KYCStep.addressEntrance), isFalse);
      expect(order.contains(KYCStep.addressReview), isTrue);
    });

    test('KYB collapses to the single premises step', () {
      final config = MyazaKYCConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
        addressCollection: const AddressCollectionConfig(enabled: true),
      );
      final order = buildStepOrder(config, const KYCState());
      // The premises pin and its directions ARE the capture on KYB, and the
      // business flow has its own section rhythm.
      expect(
        order.where(kAddressFlowOrder.contains).toList(),
        [KYCStep.addressCollection],
      );
    });

    test('joins the KYB flow as the premises step, after business details',
        () {
      final config = MyazaKYCConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
        addressCollection: const AddressCollectionConfig(enabled: true),
      );
      final order = buildStepOrder(config, const KYCState());
      final details = order.indexOf(KYCStep.businessDetails);
      expect(order.indexOf(KYCStep.addressCollection), details + 1);
    });

    test('carries the shared wire name', () {
      expect(kStepWireNames[KYCStep.addressCollection], 'address-collection');
    });
  });

  group('field modes + continue gate', () {
    test('photo and directions default to optional', () {
      expect(addressPhotoMode(null), 'optional');
      expect(addressDirectionsMode(const AddressCollectionConfig()),
          'optional');
    });

    test('the photo mode is what the entrance step gates on', () {
      // The pin step's Continue is gated on the PIN alone, and the entrance
      // step on a required photo. Required DIRECTIONS are deliberately not
      // enforced anywhere: an applicant who cannot describe the way in must
      // not be stranded by it.
      expect(addressPhotoMode(const AddressCollectionConfig(photo: 'required')),
          'required');
      expect(addressPhotoMode(const AddressCollectionConfig(photo: 'off')),
          'off');
    });
  });

  group('door photo', () {
    test('accepts images and never a PDF', () {
      expect(isAcceptedAddressPhotoMimeType('image/jpeg'), isTrue);
      expect(
          isAcceptedAddressPhotoMimeType('image/png; charset=binary'), isTrue);
      expect(isAcceptedAddressPhotoMimeType('application/pdf'), isFalse);
      expect(isAcceptedAddressPhotoMimeType(null), isFalse);
    });
  });

  group('workflow merge', () {
    test('a resolved workflow switches the step on', () {
      final merged = mergeWorkflowIntoConfig(
        _config(),
        WorkflowFlowConfig.fromJson(const {
          'country': 'NG',
          'addressCollection': {
            'enabled': true,
            'requirePin': true,
            'photo': 'off',
            'directions': 'required',
            'propertyFields': 'off',
            'streetView': 'off',
            'attestPresence': true,
            'presence': {'enabled': true},
          },
        }),
      );
      final cfg = merged.addressCollection;
      expect(cfg?.enabled, isTrue);
      expect(cfg?.requirePin, isTrue);
      expect(cfg?.photo, 'off');
      expect(cfg?.directions, 'required');
      expect(cfg?.propertyFields, 'off');
      expect(cfg?.streetView, 'off');
      expect(cfg?.attestPresence, isTrue);
      expect(cfg?.presenceEnabled, isTrue);
    });
  });
}
