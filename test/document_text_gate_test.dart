import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_framing_gate.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_text_gate.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_type_signals.dart';

// Two MRZ lines of a TD3 passport — 44 chars each, '<' fillers.
final _mrzLines = [
  'P<NGAOKAFOR<<CHIDI<<<<<<<<<<<<<<<<<<<<<<<<<<',
  'A012345678NGA9001014M3001017<<<<<<<<<<<<<<02',
];

/// Text-dense but not a document — the thing that used to trigger a capture.
final _bookPage = [
  'Chapter Four',
  'The morning had been long and the road longer still,',
  'and by the time they reached the river it was dark.',
  'She thought about the letter in her pocket.',
  'It had been three weeks since the last one arrived.',
  'Nothing about it felt final.',
];

void main() {
  group('detectDocumentType', () {
    test('identifies a Nigerian passport from its keywords', () {
      final match = detectDocumentType(
        ['FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT'],
        'NG',
      );
      expect(match.type, 'passport');
      expect(match.confidence, greaterThan(0));
    });

    test('identifies a passport in a country with no curated list', () {
      final match = detectDocumentType(_mrzLines, 'FR');
      expect(match.type, 'passport');
    });

    test('identifies a Nigerian driver licence, not a passport', () {
      final match = detectDocumentType(
        ['FEDERAL ROAD SAFETY CORPS', 'DRIVER LICENSE'],
        'NG',
      );
      expect(match.type, 'drivers-license');
    });

    test('a page of prose identifies nothing', () {
      expect(detectDocumentType(_bookPage, 'NG').type, isNull);
    });
  });

  group('DocumentTextGate identity', () {
    test('does NOT fire on text-dense non-documents', () {
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      // Well past the dwell — density alone must never be enough.
      for (var ms = 0; ms <= 3000; ms += 200) {
        final g = gate.update(
          _bookPage,
          country: 'NG',
          idType: 'passport',
          now: start.add(Duration(milliseconds: ms)),
        );
        expect(g.framing, isNot(DocumentFraming.ready));
      }
      expect(gate.hasFired, isFalse);
    });

    test('rejects a different document with a wrongDocument hint', () {
      final gate = DocumentTextGate();
      final g = gate.update(
        ['FEDERAL ROAD SAFETY CORPS', 'DRIVER LICENSE', 'FRSC'],
        country: 'NG',
        idType: 'passport',
      );
      expect(g.framing, DocumentFraming.wrongShape);
      expect(g.hint, DocumentHint.wrongDocument);
      expect(gate.hasFired, isFalse);
    });

    test('fires on the expected document once held for the dwell', () {
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      // A licence carries no MRZ, so this is the pure keyword + dwell path.
      final lines = ['FEDERAL ROAD SAFETY CORPS', 'DRIVER LICENSE', 'FRSC',
        'SURNAME', 'DATE OF BIRTH', 'CLASS'];

      final first = gate.update(lines,
          country: 'NG', idType: 'drivers-license', now: start);
      expect(first.framing, DocumentFraming.holding);

      final later = gate.update(lines,
          country: 'NG',
          idType: 'drivers-license',
          now: start.add(const Duration(milliseconds: 800)));
      expect(later.framing, DocumentFraming.ready);
    });

    test('a screen showing the WORD "passport" never fires', () {
      // The reported bug: pointing the camera at a screen of KYC text captured.
      // The word appears in prose, in code and in docs — only the machine
      // readable zone proves a passport is actually in frame.
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      final screen = [
        'The passport flow resolves via GET /api/kyc/workflows/:id',
        'idOptions: { passport: { govDbCheck: false } }',
        'requiresDocumentCapture is true for passport',
        'See the passport section of the docs for details',
        'passport, drivers-license, nin, bvn',
        'TRAVEL DOCUMENT handling is described below',
      ];
      for (var ms = 0; ms <= 3000; ms += 200) {
        final g = gate.update(screen,
            country: 'NG',
            idType: 'passport',
            now: start.add(Duration(milliseconds: ms)));
        expect(g.framing, isNot(DocumentFraming.ready));
      }
      expect(gate.hasFired, isFalse);
    });

    test('falls back to text density where no signals exist', () {
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      // FR national-id has no curated list — density must still work, or
      // Global Documents countries could never auto-capture.
      final lines = List.generate(8, (i) => 'CARTE LIGNE $i');
      gate.update(lines, country: 'FR', idType: 'national-id', now: start);
      final later = gate.update(lines,
          country: 'FR',
          idType: 'national-id',
          now: start.add(const Duration(milliseconds: 800)));
      expect(later.framing, DocumentFraming.ready);
    });
  });

  group('DocumentTextGate MRZ requirement', () {
    test('will not fire without a valid MRZ when the chip step needs one', () {
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      // A passport that reads as a passport, but whose MRZ never validated.
      final lines = ['FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT', 'SURNAME',
        'GIVEN NAMES', 'DATE OF BIRTH', 'AUTHORITY'];
      for (var ms = 0; ms <= 3000; ms += 200) {
        final g = gate.update(
          lines,
          country: 'NG',
          idType: 'passport',
          requireMrz: true,
          now: start.add(Duration(milliseconds: ms)),
        );
        expect(g.framing, isNot(DocumentFraming.ready));
      }
      expect(gate.hasFired, isFalse);
    });

    test('names the MRZ as the blocker instead of saying "move closer"', () {
      // The page is identified; only the bottom strip is missing. Telling the
      // user to move closer would push them to crop it off entirely.
      final gate = DocumentTextGate();
      final g = gate.update(
        ['FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT', 'SURNAME', 'GIVEN NAMES',
          'DATE OF BIRTH', 'AUTHORITY'],
        country: 'NG',
        idType: 'passport',
        requireMrz: true,
      );
      expect(g.hint, DocumentHint.showMrz);
      expect(g.framing, isNot(DocumentFraming.ready));
    });

    test('fires immediately once the MRZ validates', () {
      final gate = DocumentTextGate();
      final g = gate.update(
        _mrzLines,
        country: 'NG',
        idType: 'passport',
        requireMrz: true,
        hasValidMrz: true,
      );
      expect(g.framing, DocumentFraming.ready);
      expect(gate.hasFired, isTrue);
    });

    test('a stored MRZ satisfies the requirement but still earns its dwell',
        () {
      // The retake case: the chip key is already safely stored, so the gate
      // must not hold out for the MRZ again — but it must NOT fire instantly
      // either, or every retake shoots its first frame however blurry.
      final gate = DocumentTextGate();
      final start = DateTime(2026, 7, 29, 12);
      final lines = [..._mrzLines, 'FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT',
        'SURNAME', 'GIVEN NAMES'];

      final first = gate.update(lines,
          country: 'NG',
          idType: 'passport',
          requireMrz: true,
          mrzAlreadyCaptured: true,
          now: start);
      expect(first.framing, DocumentFraming.holding);

      final later = gate.update(lines,
          country: 'NG',
          idType: 'passport',
          requireMrz: true,
          mrzAlreadyCaptured: true,
          now: start.add(const Duration(milliseconds: 800)));
      expect(later.framing, DocumentFraming.ready);
    });

    test('reset re-arms after a retake', () {
      final gate = DocumentTextGate();
      gate.update(_mrzLines,
          country: 'NG', idType: 'passport', hasValidMrz: true);
      expect(gate.hasFired, isTrue);
      gate.reset();
      expect(gate.hasFired, isFalse);
      expect(gate.progress(DateTime(2026, 7, 29, 12)), 0);
    });
  });
}
