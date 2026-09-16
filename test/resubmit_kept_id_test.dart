import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/id_types.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/resubmit_kept_id.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_resubmit.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// A send-back redo that did not ask for the ID keeps the original one.
//
// The server carries `resubmit.idType` only on an individual, single-ID redo
// whose reviewer did not tick 'id-type'. When it does, the flow must not make
// the applicant pick the ID or supply its evidence again, and the submission
// names the kept ID with nothing else: the server fills in the number and the
// documents from the verification being redone. Mirrors the web and RN SDKs'
// lib/resubmit.ts.

const _order = [
  KYCStep.consent,
  KYCStep.idType,
  KYCStep.documentCapture,
  KYCStep.liveness,
  KYCStep.submitted,
];

ResubmitConfig _plan(List<String> steps, [String? idType]) =>
    ResubmitConfig(steps: steps, idType: idType);

MyazaKYCConfig _config({
  ResubmitConfig? resubmit,
  String country = 'NG',
  String subjectType = 'individual',
  bool consentStep = true,
}) =>
    MyazaKYCConfig(
      apiKey: 'pk_test_x',
      country: country,
      resubmit: resubmit,
      subjectType: subjectType,
      consentStep: consentStep,
    );

void main() {
  group('keptIdType', () {
    test('returns the idType the server carried', () {
      expect(keptIdType(_plan(['liveness'], 'bvn')), 'bvn');
    });

    test('is null when the server sent none', () {
      expect(keptIdType(_plan(['liveness'])), isNull);
      expect(keptIdType(_plan(['liveness'], '  ')), isNull);
    });

    test('is null when the reviewer ticked the ID picker', () {
      expect(keptIdType(_plan(['id-type', 'liveness'], 'bvn')), isNull);
    });

    test('is null with no plan at all', () {
      expect(keptIdType(_plan([], 'bvn')), isNull);
      expect(keptIdType(null), isNull);
    });

    test('is parsed from the session snapshot', () {
      final parsed = ResubmitConfig.fromJson({
        'steps': ['liveness'],
        'idType': 'passport',
      });
      expect(keptIdType(parsed), 'passport');
      // An idType that is not a string is not an instruction.
      expect(ResubmitConfig.fromJson({'steps': ['liveness'], 'idType': 7})!.idType, isNull);
    });
  });

  group('narrowing a redo that keeps the ID', () {
    test('walks only the frame and what was asked when no evidence was asked', () {
      expect(
        applyResubmitSteps(_order, _plan(['liveness'], 'passport')),
        [KYCStep.consent, KYCStep.liveness, KYCStep.submitted],
      );
    });

    test('keeps the evidence family when evidence was asked, but not the picker', () {
      const withChip = [
        KYCStep.consent,
        KYCStep.idType,
        KYCStep.documentCapture,
        KYCStep.nfc,
        KYCStep.liveness,
        KYCStep.submitted,
      ];
      expect(
        applyResubmitSteps(withChip, _plan(['document-capture'], 'passport')),
        [KYCStep.consent, KYCStep.documentCapture, KYCStep.nfc, KYCStep.submitted],
      );
    });

    test('keeps the number step for a number-only kept ID', () {
      const numberOnly = [
        KYCStep.consent,
        KYCStep.idType,
        KYCStep.idInput,
        KYCStep.liveness,
        KYCStep.submitted,
      ];
      expect(
        applyResubmitSteps(numberOnly, _plan(['id-input'], 'bvn')),
        [KYCStep.consent, KYCStep.idInput, KYCStep.submitted],
      );
    });

    test('still runs everything for a plan naming nothing this flow has', () {
      expect(applyResubmitSteps(_order, _plan(['future-step'], 'passport')), _order);
      expect(applyResubmitSteps(_order, _plan(['consent'], 'passport')), _order);
    });
  });

  group('narrowing without a kept ID', () {
    test('keeps the ID steps, as before', () {
      expect(
        applyResubmitSteps(_order, _plan(['liveness'])),
        [
          KYCStep.consent,
          KYCStep.idType,
          KYCStep.documentCapture,
          KYCStep.liveness,
          KYCStep.submitted,
        ],
      );
    });

    test('keeps the picker when the reviewer ticked it, whatever was sent', () {
      expect(
        applyResubmitSteps(_order, _plan(['id-type', 'liveness'], 'passport')),
        [
          KYCStep.consent,
          KYCStep.idType,
          KYCStep.documentCapture,
          KYCStep.liveness,
          KYCStep.submitted,
        ],
      );
    });
  });

  group('a business redo', () {
    test('is unchanged by an idType it should never be sent', () {
      const kyb = [
        KYCStep.consent,
        KYCStep.businessDetails,
        KYCStep.businessDocuments,
        KYCStep.applicantRole,
        KYCStep.idType,
        KYCStep.documentCapture,
        KYCStep.liveness,
        KYCStep.submitted,
      ];
      for (final steps in [
        ['business-documents'],
        ['liveness'],
      ]) {
        expect(
          applyResubmitSteps(kyb, _plan(steps, 'passport')),
          applyResubmitSteps(kyb, _plan(steps)),
        );
      }
    });

    test('never preselects an ID', () {
      const initial = KYCState();
      final config = _config(resubmit: _plan(['liveness'], 'passport'), subjectType: 'business');
      expect(identical(withKeptIdType(config, initial), initial), isTrue);
    });
  });

  group('carriesIdEvidence', () {
    test('is true when the ID is kept and no evidence was asked', () {
      expect(carriesIdEvidence(_plan(['liveness'], 'passport')), isTrue);
    });

    test('is false when the reviewer asked for the evidence again', () {
      for (final step in ['document-capture', 'id-input', 'nfc']) {
        expect(carriesIdEvidence(_plan([step, 'liveness'], 'passport')), isFalse, reason: step);
      }
    });

    test('is false when the ID is not kept', () {
      expect(carriesIdEvidence(_plan(['liveness'])), isFalse);
      expect(carriesIdEvidence(_plan(['id-type', 'liveness'], 'passport')), isFalse);
      expect(carriesIdEvidence(null), isFalse);
    });
  });

  group('preselecting the kept ID', () {
    test('selects it when nothing is selected', () {
      final seeded = withKeptIdType(_config(resubmit: _plan(['liveness'], 'bvn')), const KYCState());
      expect(seeded.selectedIdType?.key, 'bvn');
      expect(seeded.selectedIdType?.requiresDocumentCapture, isFalse);
    });

    test('never replaces a different selection', () {
      final picked = KYCState(selectedIdType: resolveIdTypeDefinition('NG', 'passport'));
      final config = _config(resubmit: _plan(['liveness'], 'bvn'));
      expect(identical(withKeptIdType(config, picked), picked), isTrue);
    });

    test('leaves a redo without a kept ID alone', () {
      const initial = KYCState();
      expect(identical(withKeptIdType(_config(resubmit: _plan(['liveness'])), initial), initial), isTrue);
      expect(identical(withKeptIdType(_config(), initial), initial), isTrue);
    });

    test('takes the server row for an ID with no curated definition', () {
      const state = KYCState(
        serverConfig: ServerSdkConfig(
          status: ServerConfigStatus.ready,
          idTypes: [
            SdkConfigIdType(
              country: 'FR',
              idType: 'national-id',
              features: SdkIdTypeFeatures(
                documentVerification: true,
                livenessCheck: true,
                govDbCheck: false,
              ),
              label: 'Carte nationale',
              scanSides: 'front_and_back',
              supportsNfc: true,
            ),
          ],
        ),
      );
      final config = _config(country: 'FR', resubmit: _plan(['document-capture'], 'national-id'));
      final def = withKeptIdType(config, state).selectedIdType!;
      expect(def.label, 'Carte nationale');
      expect(def.scanSides, ScanSides.frontAndBack);
      expect(def.supportsNfc, isTrue);
    });

    test('opens on the first step the kept ID actually has', () {
      // Consent is off and the reviewer asked for the number. Before any ID is
      // chosen the flow is shaped for a document; a BVN has no such step.
      final config = _config(consentStep: false, resubmit: _plan(['id-input'], 'bvn'));
      final initial = KYCState(currentStep: openingStep(config));
      expect(initial.currentStep, KYCStep.documentCapture);
      expect(seedKeptIdType(config, initial).currentStep, KYCStep.idInput);
    });

    test('keeps an opening step that still exists', () {
      final config = _config(resubmit: _plan(['liveness'], 'bvn'));
      final initial = KYCState(currentStep: openingStep(config));
      final seeded = seedKeptIdType(config, initial);
      expect(seeded.currentStep, KYCStep.consent);
      expect(buildStepOrder(config, seeded), [KYCStep.consent, KYCStep.liveness, KYCStep.submitted]);
    });
  });

  group('the submission names the kept ID and nothing else', () {
    // A SOURCE test, like multi_id_submit_guard_test: the rule is a condition
    // in a method that needs a provider, a store and a network to reach.
    final source = File('lib/src/providers/kyc_provider.dart').readAsStringSync();

    test('reads the carry rule from the reviewer instruction', () {
      expect(source.contains('final carried = carriesIdEvidence(_config.resubmit);'), isTrue);
    });

    test('does not demand a number for a carried ID', () {
      expect(source.contains('if (carried) {'), isTrue);
    });

    test('sends no document media or chip read for a carried ID', () {
      expect(source.contains('documentFront: multiSlots == null && !carried'), isTrue);
      expect(source.contains('documentBack: multiSlots == null && !carried'), isTrue);
      expect(source.contains('documentFrontVideo: carried ? null : mediaIds.documentFrontVideo'), isTrue);
      expect(source.contains('documentBackVideo: carried ? null : mediaIds.documentBackVideo'), isTrue);
      expect(source.contains('!carried &&'), isTrue);
    });

    test('seeds the kept ID at flow start and on reset', () {
      expect(RegExp(r'seedKeptIdType\(').allMatches(source).length, 2);
      expect(source.contains('state = withKeptIdType(_config, state);'), isTrue);
    });
  });
}
