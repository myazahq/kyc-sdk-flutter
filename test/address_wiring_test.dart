import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_flow.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/address_step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/step_log.dart';

// ─── The address flow, wired into the step machine ───────────────────────────
//
// The four screens are REAL steps, so entering, leaving and going back are
// ordinary step navigation. These tests pin the seams that carry that: what
// the order contains, what the progress bar counts, and where a resumed
// session is allowed to land.

MyazaKYCConfig _individual({
  String? photo,
  bool proofOfAddress = false,
  bool questionnaire = false,
}) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      addressCollection:
          AddressCollectionConfig(enabled: true, photo: photo),
      proofOfAddress:
          proofOfAddress ? const ProofOfAddressConfig(enabled: true) : null,
      questionnaire: questionnaire
          ? QuestionnaireConfig.fromJson(const {
              'fields': [
                {'key': 'source_of_funds', 'label': 'Source', 'type': 'text'},
              ],
            })
          : null,
    );

MyazaKYCConfig _business() => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      subjectType: 'business',
      business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
      addressCollection: const AddressCollectionConfig(enabled: true),
    );

KYCState _withSearch() => const KYCState(
      serverConfig: ServerSdkConfig(
        status: ServerConfigStatus.ready,
        addressSearch: true,
        addressSearchMode: 'basic',
      ),
    );

void main() {
  group('wire names', () {
    test('are the canonical four, in flow order', () {
      // The server's timeline titles and every session snapshot key off these,
      // so Flutter must never leak its camelCase enum names. A CROSS-SDK
      // MIRROR: the same four strings appear in the web and RN SDKs.
      expect(
        [for (final step in kAddressFlowOrder) kStepWireNames[step]],
        ['address-search', 'address-collection', 'address-entrance',
         'address-review'],
      );
    });

    test('the pin step keeps the ORIGINAL name though it moved second', () {
      // Session progress saved by a build that had one address screen restores
      // onto this one. Renaming it would strand every one of those snapshots.
      expect(kStepWireNames[KYCStep.addressCollection], 'address-collection');
    });
  });

  group('entering and leaving', () {
    test('the flow is entered at its FIRST step, not at the pin', () {
      // Routing straight to the pin skips the search entirely. `nextStep`
      // indexes into this order, so what follows Proof of Address IS where the
      // applicant lands.
      final order = buildStepOrder(
        _individual(proofOfAddress: true),
        _withSearch(),
      );
      final poa = order.indexOf(KYCStep.proofOfAddress);
      expect(order[poa + 1], KYCStep.addressSearch);
    });

    test('backing in from the questionnaire lands on the review', () {
      // `previousStep` indexes into the same order, so the step before the
      // questionnaire is where a back press from it arrives.
      final order = buildStepOrder(
        _individual(questionnaire: true),
        _withSearch(),
      );
      final questionnaire = order.indexOf(KYCStep.questionnaire);
      expect(order[questionnaire - 1], KYCStep.addressReview);
    });

    test('the whole flow sits contiguously in the order', () {
      final order = buildStepOrder(
        _individual(proofOfAddress: true, questionnaire: true),
        _withSearch(),
      );
      final poa = order.indexOf(KYCStep.proofOfAddress);
      final questionnaire = order.indexOf(KYCStep.questionnaire);
      expect(order.sublist(poa + 1, questionnaire), kAddressFlowOrder);
    });
  });

  group('the progress indicator', () {
    test('counts every address step', () {
      // The bar reads the same `buildStepOrder` navigation does, minus the
      // terminal step. Four screens the applicant walks are four it must count.
      int countable(MyazaKYCConfig config, KYCState state) =>
          buildStepOrder(config, state)
              .where((s) => s != KYCStep.submitted)
              .length;

      final withFlow = countable(_individual(), _withSearch());
      final withoutFlow = countable(
        const MyazaKYCConfig(
          apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          country: 'NG',
        ),
        _withSearch(),
      );
      expect(withFlow - withoutFlow, 4);
    });

    test('every step it counts can be placed in the order', () {
      // A step absent from the order has no index, so the bar cannot place it
      // and both next and back become no-ops. That is the dead end the resume
      // clamp below exists to prevent.
      final order = buildStepOrder(_individual(), _withSearch());
      for (final step in kAddressFlowOrder) {
        expect(order.indexOf(step), greaterThan(-1), reason: '$step');
      }
    });
  });

  group('KYB collapses to the premises step', () {
    test('offers the pin and nothing else', () {
      expect(addressStepsFor(_business(), const KYCState()),
          [KYCStep.addressCollection]);
    });

    test('the collapse survives a search backend and a photo slot', () {
      // Both would add a step to an individual flow. A KYB premises capture is
      // the pin and its directions, whatever else is switched on.
      final config = MyazaKYCConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
        addressCollection:
            const AddressCollectionConfig(enabled: true, photo: 'required'),
      );
      expect(buildStepOrder(config, _withSearch())
          .where(kAddressFlowOrder.contains)
          .toList(),
          [KYCStep.addressCollection]);
    });

    test('the pin step is therefore the one that COMMITS', () {
      // The screen asks the flow, not the subject type: nothing follows the
      // pin here, so its Continue takes the attest fix and stores the presence
      // pin rather than advancing.
      final offered = addressStepsFor(_business(), const KYCState());
      expect(nextAddressStep(offered, KYCStep.addressCollection), isNull);
    });

    test('on an individual flow the review commits instead', () {
      final offered = addressStepsFor(_individual(), _withSearch());
      expect(nextAddressStep(offered, KYCStep.addressCollection), isNotNull);
      expect(nextAddressStep(offered, KYCStep.addressReview), isNull);
    });
  });

}
