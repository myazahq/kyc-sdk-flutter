import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/inferred_country.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/proof_of_address.dart';

// The offered document kinds follow the COUNTRY (an org may accept different
// papers per market), and the accepted-country list is what the address
// scope's picker offers. Mirrors the web/RN rules — keep the three in lockstep.

void main() {
  final poa = ProofOfAddressConfig.fromJson({
    'enabled': true,
    'documentTypes': ['utility_bill'],
    'countryDocuments': {
      'gb': ['bank_statement', 'other'],
      'NG': <String>[],
    },
    'countries': ['ng', 'GB'],
  });

  group('offeredTypesFor', () {
    test("a country's override replaces the global list for it alone", () {
      expect(poa.offeredTypesFor('gb'),
          [PoaDocumentType.bankStatement, PoaDocumentType.other]);
      expect(poa.offeredTypesFor('KE'), [PoaDocumentType.utilityBill]);
      expect(poa.offeredTypesFor(null), [PoaDocumentType.utilityBill]);
    });

    test('an empty override falls through to the global list', () {
      expect(poa.offeredTypesFor('NG'), [PoaDocumentType.utilityBill]);
    });
  });

  group('countryAccepted', () {
    test('case-insensitive, and an empty list accepts everyone', () {
      expect(poa.countries, ['NG', 'GB']);
      expect(poa.countryAccepted('gb'), isTrue);
      expect(poa.countryAccepted('KE'), isFalse);
      expect(poa.countryAccepted(null), isTrue);
      expect(const ProofOfAddressConfig(enabled: true).countryAccepted('KE'),
          isTrue);
    });
  });

  group('inferredCountry', () {
    test('prefers the server geo answer, else the device region', () {
      expect(inferredCountry(' ng ', deviceCountry: 'GB'), 'NG');
      expect(inferredCountry(null, deviceCountry: 'gb'), 'GB');
    });

    test('returns null when nothing can say', () {
      expect(inferredCountry('419', deviceCountry: '419'), isNull);
      expect(inferredCountry('', deviceCountry: ''), isNull);
    });
  });

  group('kinds this build does not know', () {
    final newer = ProofOfAddressConfig.fromJson({
      'enabled': true,
      'documentTypes': ['utility_bill', 'holographic_deed'],
      'countryDocuments': {'NG': ['holographic_deed']},
    });

    test('are hidden rather than drawn as a second "Other document"', () {
      expect(newer.offeredTypes, [PoaDocumentType.utilityBill]);
    });

    test('an override made only of unknown kinds falls through, never to nothing', () {
      expect(newer.offeredTypesFor('NG'), [PoaDocumentType.utilityBill]);
    });

    test('government_document is a kind of its own', () {
      expect(PoaDocumentType.fromKey('government_document'),
          PoaDocumentType.governmentDocument);
      expect(PoaDocumentType.governmentDocument.key, 'government_document');
    });
  });

  group('namePolicyFor', () {
    final ruled = ProofOfAddressConfig.fromJson({
      'enabled': true,
      'nameMatch': 'optional',
      'countryNameMatch': {
        'ng': {'utility_bill': 'off', 'other': 'nonsense'},
      },
    });

    test('is required when the workflow says nothing', () {
      expect(poa.namePolicyFor('NG', PoaDocumentType.utilityBill),
          PoaNameRule.required);
    });

    test("a country's per-kind exception beats the default for that kind alone", () {
      expect(ruled.namePolicyFor('ng', PoaDocumentType.utilityBill),
          PoaNameRule.off);
      expect(ruled.namePolicyFor('NG', PoaDocumentType.bankStatement),
          PoaNameRule.optional);
      expect(ruled.namePolicyFor('GH', PoaDocumentType.utilityBill),
          PoaNameRule.optional);
    });

    test('an unrecognised rule is dropped at parse rather than trusted', () {
      expect(ruled.namePolicyFor('NG', PoaDocumentType.other),
          PoaNameRule.optional);
    });
  });
}
