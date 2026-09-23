import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/supporting_documents.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/workflow_merge.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_progress.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_restore.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// ─── Supporting documents ────────────────────────────────────────────────────
//
// The FOURTH mirror of one resolution rule (server, web SDK, RN SDK, here).
// These assertions are the RN suite's, so a rule that drifts in one language
// fails in that language's own words.

final nin = idComposite('NG', 'nin');
final bvn = idComposite('NG', 'bvn');

// The organisation names its own documents; nothing in the SDK knows the key.
SupportingDocumentsConfig _ninSlipOnly() => SupportingDocumentsConfig.fromJson({
      'enabled': true,
      'types': [
        {
          'key': 'nin_slip',
          'label': 'NIN slip',
          'description': 'The slip NIMC issued with your NIN.',
          'required': true,
          'idTypes': [nin],
        },
      ],
    })!;

MyazaKYCConfig _config({SupportingDocumentsConfig? docs}) => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      supportingDocuments: docs,
    );

void main() {
  _readsTests();

  group('resolveSupportingDocuments', () {
    test('asks for nothing when the step is off', () {
      expect(resolveSupportingDocuments(null, [nin]), isEmpty);
      final offByDefault = SupportingDocumentsConfig.fromJson({
        'types': [
          {'key': 'nin_slip', 'label': 'NIN slip'},
        ],
      });
      expect(resolveSupportingDocuments(offByDefault, [nin]), isEmpty);
    });

    test('asks a scoped document only of the IDs it names', () {
      final asked = resolveSupportingDocuments(_ninSlipOnly(), [nin]);
      expect(asked.map((d) => d.key), ['nin_slip']);
      expect(asked.single.label, 'NIN slip');
      expect(asked.single.description, 'The slip NIMC issued with your NIN.');
      expect(asked.single.required, isTrue);
      // A BVN applicant has no NIN slip, so asking would be a dead end.
      expect(resolveSupportingDocuments(_ninSlipOnly(), [bvn]), isEmpty);
    });

    test('offers a scoped document to everyone when the author says always ask', () {
      // The scope then decides who MUST provide it, not who sees it: an org
      // that needs the slip from NIN verifiers will still take one from
      // anybody who happens to hold it.
      final config = SupportingDocumentsConfig.fromJson({
        'enabled': true,
        'types': [
          {
            'key': 'nin_slip',
            'label': 'NIN slip',
            'required': true,
            'idTypes': [nin],
            'alwaysAsk': true,
          },
        ],
      })!;
      expect(resolveSupportingDocuments(config, [nin]).single.required, isTrue);

      final asked = resolveSupportingDocuments(config, [bvn]).single;
      expect(asked.key, 'nin_slip');
      // Never blocked for not having a document their ID does not come with.
      expect(asked.required, isFalse);
    });

    test('asks an unscoped document of everyone', () {
      final config = SupportingDocumentsConfig.fromJson({
        'enabled': true,
        'types': [
          {'key': 'signed_mandate', 'label': 'Signed mandate'},
        ],
      });
      final asked = resolveSupportingDocuments(config, [bvn]);
      expect(asked.single.label, 'Signed mandate');
      expect(asked.single.description, isNull);
      expect(asked.single.required, isFalse);
    });

    test('asks once when a multi-ID run matches twice', () {
      final config = SupportingDocumentsConfig.fromJson({
        'enabled': true,
        'types': [
          {'key': 'nin_slip', 'label': 'NIN slip', 'idTypes': [nin]},
          {'key': 'nin_slip', 'label': 'NIN slip', 'idTypes': [bvn]},
        ],
      });
      expect(resolveSupportingDocuments(config, [nin, bvn]), hasLength(1));
    });

    test('drops an entry the applicant could not read rather than showing it', () {
      // A title is the only thing that names the document, so a nameless entry
      // reaches nobody. Publish refuses one; this only bites a draft mid-edit.
      final config = SupportingDocumentsConfig.fromJson({
        'enabled': true,
        'types': [
          {'key': 'bank_mandate'},
          {'key': 'nin_slip', 'label': 'NIN slip'},
        ],
      });
      expect(resolveSupportingDocuments(config, [nin]).map((d) => d.key), ['nin_slip']);
    });
  });

  group('verifiedIdsFor', () {
    test('is the picked ID, or every committed slot', () {
      expect(verifiedIdsFor(country: 'NG', idType: 'nin'), [nin]);
      expect(
        verifiedIdsFor(country: 'NG', idType: 'nin', multiIdTypes: ['nin', 'bvn']),
        [nin, bvn],
      );
    });

    test('is empty before a country is known', () {
      expect(verifiedIdsFor(country: null, idType: 'nin'), isEmpty);
    });
  });

  group('the step in the order', () {
    KYCState picked(String idType) =>
        KYCState(selectedIdType: resolveIdTypeDefinition('NG', idType));

    test('is absent while nothing resolves to ask for', () {
      expect(
        buildStepOrder(_config(), picked('nin')),
        isNot(contains(KYCStep.supportingDocuments)),
      );
      // The switch is on, but this applicant used a BVN.
      expect(
        buildStepOrder(_config(docs: _ninSlipOnly()), picked('bvn')),
        isNot(contains(KYCStep.supportingDocuments)),
      );
    });

    test('sits after the checks, and before proof of address', () {
      // Paperwork the org files is asked for ahead of the address evidence the
      // verification is judged on (user decision 2026-09-22).
      final order = buildStepOrder(
        _config(docs: _ninSlipOnly()).copyWith(
          proofOfAddress: const ProofOfAddressConfig(enabled: true),
        ),
        picked('nin'),
      );
      expect(order, contains(KYCStep.supportingDocuments));
      expect(
        order.indexOf(KYCStep.supportingDocuments),
        greaterThan(order.indexOf(KYCStep.liveness)),
      );
      expect(
        order.indexOf(KYCStep.supportingDocuments),
        lessThan(order.indexOf(KYCStep.proofOfAddress)),
      );
    });

    test('hasSupportingDocumentsStep is the resolution, not the switch', () {
      expect(hasSupportingDocumentsStep(_ninSlipOnly(), [bvn]), isFalse);
      expect(hasSupportingDocumentsStep(_ninSlipOnly(), [nin]), isTrue);
    });
  });

  test('a resolved workflow carries the block through the merge', () {
    final merged = mergeWorkflowIntoConfig(
      _config(),
      const WorkflowFlowConfig(
        raw: {
          'country': 'NG',
          'supportingDocuments': {
            'enabled': true,
            'types': [
              {'key': 'nin_slip', 'label': 'NIN slip', 'required': true},
            ],
          },
        },
      ),
    );
    expect(merged.supportingDocuments?.enabled, isTrue);
    expect(merged.supportingDocuments?.types.single.key, 'nin_slip');
    expect(merged.supportingDocuments?.types.single.label, 'NIN slip');
  });

  group('the uploads survive a resume', () {
    test('ride progress as ids alone and restore without a preview', () {
      final state = const KYCState().copyWith(
        supportingDocuments: const [
          SupportingDocumentUpload(
            type: 'nin_slip',
            mediaId: 'med_1',
            fileName: 'nin_slip.jpg',
            previewPath: '/tmp/nin_slip.jpg',
          ),
        ],
      );
      final saved = progressFromState(state);
      final data = (saved['data'] as Map)['supportingDocuments'] as List;
      expect(data.single, {'type': 'nin_slip', 'mediaId': 'med_1'});

      final restored = restoredState(const KYCState(), saved);
      expect(restored.supportingDocuments.single.mediaId, 'med_1');
      expect(restored.supportingDocuments.single.previewPath, isNull);
    });

    test('a row with no mediaId is dropped rather than half-restored', () {
      final restored = restoredState(const KYCState(), {
        'step': 'supporting-documents',
        'mediaIds': const {},
        'data': {
          'supportingDocuments': [
            {'type': 'nin_slip'},
            {'type': 'other', 'mediaId': 'med_2'},
          ],
        },
      });
      expect(restored.supportingDocuments.map((d) => d.type), ['other']);
    });
  });
}

// ─── What the applicant is told a document is for ────────────────────────────
//
// A supporting document is whatever the organisation named it, so naming the
// values that will be read off it is what says what handing it over is FOR.
// Display only: the server decides what is actually read.
void _readsTests() {
  group('what the applicant is told a document is for', () {
    final statement = SupportingDocumentsConfig.fromJson({
      'enabled': true,
      'types': [
        {
          'key': 'proof_of_funds',
          'label': 'Proof of funds',
          'fields': [
            {'key': 'holder', 'label': 'Account holder'},
            {'key': 'bank', 'label': 'Bank name'},
            // Blank and repeated names reach nobody, so neither is shown.
            {'key': 'blank', 'label': '  '},
            {'key': 'again', 'label': 'bank name'},
            {'key': 'nameless'},
          ],
        },
      ],
    });

    test('names the values the server will read off it', () {
      expect(
        resolveSupportingDocuments(statement, [nin]).single.reads,
        ['Account holder', 'Bank name'],
      );
    });

    test('says nothing when the document is only being stored', () {
      final stored = SupportingDocumentsConfig.fromJson({
        'enabled': true,
        'types': [
          {'key': 'a', 'label': 'Signature'},
        ],
      });
      expect(resolveSupportingDocuments(stored, [nin]).single.reads, isEmpty);
    });
  });
}
