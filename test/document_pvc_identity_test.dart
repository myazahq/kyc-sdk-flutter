import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_identity.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_type_signals.dart';

// ─── Identifying a voter's card ───────────────────────────────────────────────
//
// Auto-capture was noticeably slower on a PVC than on a passport, and the cause
// was arithmetic rather than the camera: confidence is matched/total, so the
// voter card's eight synonyms meant THREE hits were needed where the passport
// needed two — one of which its MRZ supplies for free. The more thorough the
// keyword list, the harder the document was to recognise.

/// What a phone resolves FIRST off a PVC: the large title. The VIN, the
/// commission's name and the rest are small print on a holographic card and
/// arrive later, if at all — so this is the frame the gate has to decide on.
const _sparsePvc = [
  'FEDERAL REPUBLIC OF NIGERIA',
  "VOTER'S CARD",
];

void main() {
  group('voter card', () {
    test('two hits identify it, without needing a third', () {
      final match = detectDocumentType(_sparsePvc, 'NG');
      expect(match.type, 'pvc');
      expect(match.matched, greaterThanOrEqualTo(2));
      // The ratio alone would NOT have cleared the 0.34 bar.
      expect(match.confidence, lessThan(0.34));

      final id = verifyDocumentIdentity(_sparsePvc, country: 'NG', idType: 'pvc');
      expect(id.identified, isTrue,
          reason: 'a card that plainly says it is a voter card must fire');
    });

    test('a single weak hit is still not enough', () {
      final id = verifyDocumentIdentity(
        const ['FEDERAL REPUBLIC OF NIGERIA', 'SOME OTHER TEXT', 'VOTER'],
        country: 'NG',
        idType: 'pvc',
      );
      expect(id.identified, isFalse,
          reason: 'one word is not evidence of a document');
    });
  });

  group('short acronyms match on word boundaries', () {
    test("a driver's licence does not read as a voter card", () {
      // "VIN" sits inside "driVINg" — as a bare substring it scored a PVC hit,
      // which becomes a wrong identification once hits are counted directly.
      const dl = [
        'FEDERAL REPUBLIC OF NIGERIA',
        'DRIVING LICENCE',
        'FEDERAL ROAD SAFETY CORPS',
      ];
      expect(countSignalHits(dl.join('\n').toUpperCase(), const ['VIN']), 0);

      final match = detectDocumentType(dl, 'NG');
      expect(match.type, 'drivers-license');
    });

    test('a real VIN label still counts', () {
      expect(countSignalHits('VIN: INC2 2000', const ['VIN']), 1);
    });
  });

  test('the passport MRZ rule is unchanged', () {
    // Counting hits must not let a passport fire without its machine-readable
    // zone — that rule is what stops a screen full of prose identifying as one.
    final id = verifyDocumentIdentity(
      const ['FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT', 'TRAVEL DOCUMENT'],
      country: 'NG',
      idType: 'passport',
    );
    expect(id.identified, isFalse);
  });
}
