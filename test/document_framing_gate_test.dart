import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_detection.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/document_framing_gate.dart';

const _cardAspect = 1.586;

/// A detection with an explicit normalized footprint, centred unless moved.
/// [aspectRatio] is the document's TRUE shape (native reports it in oriented
/// pixels) and is deliberately independent of [w]/[h] — the normalized box is
/// skewed by the frame's own aspect, which is exactly why the gate can't infer
/// shape from it.
///
/// Defaults describe a well-framed card: area 0.35, ≥0.15 margin on every edge.
DocumentBox _box({
  double w = 0.7,
  double h = 0.5,
  double centerX = 0.5,
  double centerY = 0.5,
  double confidence = 0.9,
  double aspectRatio = _cardAspect,
}) {
  return DocumentBox(
    x: centerX - w / 2,
    y: centerY - h / 2,
    width: w,
    height: h,
    confidence: confidence,
    aspectRatio: aspectRatio,
  );
}

DocumentFramingGate _gate({Duration? dwell}) => DocumentFramingGate(
      expectedAspect: _cardAspect,
      dwell: dwell ?? const Duration(milliseconds: 900),
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  group('shape awareness', () {
    test('accepts something the right shape for an ID card', () {
      expect(_gate().update(_box(), at: t0).framing, DocumentFraming.holding);
    });

    test('rejects a near-square object (a book, a coaster)', () {
      expect(_gate().update(_box(aspectRatio: 1.05), at: t0).framing, DocumentFraming.wrongShape);
    });

    test('rejects a long receipt', () {
      expect(_gate().update(_box(aspectRatio: 3.2), at: t0).framing, DocumentFraming.wrongShape);
    });

    test('rejects an A4 page held landscape (1.41 is close but not a card)', () {
      // A4 landscape is 1.414 — inside a naive ±30% band of 1.586, so this
      // pins that the passport gate (1.42) and the card gate stay distinct.
      final passportGate = DocumentFramingGate(
        expectedAspect: 1.42,
        aspectTolerance: 0.10,
      );
      expect(passportGate.matchesShape(_box(aspectRatio: 1.414)), isTrue);
      final cardGate = DocumentFramingGate(
        expectedAspect: _cardAspect,
        aspectTolerance: 0.08,
      );
      expect(cardGate.matchesShape(_box(aspectRatio: 1.414)), isFalse);
    });

    test('tolerates perspective skew on a real card', () {
      expect(_gate().matchesShape(_box(aspectRatio: 1.40)), isTrue);
      expect(_gate().matchesShape(_box(aspectRatio: 1.80)), isTrue);
    });
  });

  group('framing', () {
    test('reports none when nothing is detected', () {
      expect(_gate().update(null, at: t0).framing, DocumentFraming.none);
    });

    test('ignores a low-confidence detection', () {
      expect(_gate().update(_box(confidence: 0.2), at: t0).framing, DocumentFraming.none);
    });

    test('asks to adjust when the document is too small', () {
      // area 0.03 — the crop would lose the detail OCR needs.
      expect(_gate().update(_box(w: 0.2, h: 0.15), at: t0).framing, DocumentFraming.adjust);
    });

    test('asks to adjust when the document overflows the frame', () {
      // area 0.94 and hard against the borders: corners are already cut.
      expect(_gate().update(_box(w: 0.99, h: 0.95), at: t0).framing, DocumentFraming.adjust);
    });

    test('asks to adjust when an edge is flush with the frame border', () {
      // Wide enough to touch the left edge → a corner is out of shot.
      const flush = DocumentBox(
        x: 0.0,
        y: 0.3,
        width: 0.6,
        height: 0.4,
        confidence: 0.9,
        aspectRatio: _cardAspect,
      );
      expect(_gate().update(flush, at: t0).framing, DocumentFraming.adjust);
    });

    test('asks to adjust when off centre', () {
      // Sized and inset so ONLY the centring rule fails — area 0.245 and every
      // edge still clear, isolating the behaviour under test.
      expect(_gate().update(_box(w: 0.7, h: 0.35, centerY: 0.79), at: t0).framing, DocumentFraming.adjust);
    });
  });

  group('hints', () {
    test('names the actual problem instead of a generic prompt', () {
      // The reported UX failure: too close reads as "not working", and the
      // instinct is to move NEARER. The gate must say move back.
      expect(
        _gate().update(_box(w: 0.99, h: 0.95), at: t0).hint,
        DocumentHint.moveBack,
      );
      expect(
        _gate().update(_box(w: 0.2, h: 0.15), at: t0).hint,
        DocumentHint.moveCloser,
      );
      expect(
        _gate().update(_box(w: 0.7, h: 0.35, centerY: 0.79), at: t0).hint,
        DocumentHint.centre,
      );
      expect(
        _gate().update(_box(aspectRatio: 1.05), at: t0).hint,
        DocumentHint.wrongDocument,
      );
    });

    test('asks for light when the frame is dark and nothing is found', () {
      expect(
        _gate().update(null, at: t0, brightness: 0.05).hint,
        DocumentHint.moreLight,
      );
    });

    test('stays neutral when nothing is found but the light is fine', () {
      expect(
        _gate().update(null, at: t0, brightness: 0.6).hint,
        DocumentHint.searching,
      );
    });

    test('asks for light rather than firing on a well-framed dark shot', () {
      final g = _gate(dwell: Duration.zero);
      final out = g.update(_box(), at: t0, brightness: 0.05);
      expect(out.hint, DocumentHint.moreLight);
      expect(out.framing, DocumentFraming.adjust);
      expect(g.hasFired, isFalse, reason: 'must not capture a too-dark frame');
    });

    test('prefers move-back over centring when the document overflows', () {
      // An overflowing document is usually off-centre too; "move back" is the
      // instruction that actually resolves it.
      const overflowing = DocumentBox(
        x: -0.05,
        y: 0.0,
        width: 1.0,
        height: 0.95,
        confidence: 0.9,
        aspectRatio: _cardAspect,
      );
      expect(
        _gate().update(overflowing, at: t0).hint,
        DocumentHint.moveBack,
      );
    });

    test('reports hold-still while the dwell runs', () {
      expect(_gate().update(_box(), at: t0).hint, DocumentHint.holdStill);
    });
  });

  group('stability', () {
    test('holds before firing, then fires after the dwell', () {
      final gate = _gate(dwell: const Duration(seconds: 1));
      expect(gate.update(_box(), at: t0).framing, DocumentFraming.holding);
      expect(gate.update(_box(), at: t0.add(const Duration(milliseconds: 500))).framing, DocumentFraming.holding);
      expect(gate.update(_box(), at: t0.add(const Duration(milliseconds: 1000))).framing, DocumentFraming.ready);
    });

    test('a document that drifts away restarts the dwell', () {
      final gate = _gate(dwell: const Duration(seconds: 1));
      gate.update(_box(), at: t0);
      expect(gate.update(_box(centerX: 0.95),
            at: t0.add(const Duration(milliseconds: 900))).framing, DocumentFraming.adjust);
      expect(gate.update(_box(), at: t0.add(const Duration(milliseconds: 950))).framing, DocumentFraming.holding);
      expect(gate.update(_box(), at: t0.add(const Duration(milliseconds: 1960))).framing, DocumentFraming.ready);
    });

    test('a wrong-shaped object mid-dwell restarts it', () {
      final gate = _gate(dwell: const Duration(seconds: 1));
      gate.update(_box(), at: t0);
      expect(gate.update(_box(aspectRatio: 1.0),
            at: t0.add(const Duration(milliseconds: 800))).framing, DocumentFraming.wrongShape);
      expect(gate.update(_box(), at: t0.add(const Duration(milliseconds: 850))).framing, DocumentFraming.holding);
    });

    test('latches after firing so capture cannot double-trigger', () {
      final gate = _gate(dwell: Duration.zero);
      expect(gate.update(_box(), at: t0).framing, DocumentFraming.ready);
      expect(gate.hasFired, isTrue);
      expect(gate.update(null, at: t0).framing, DocumentFraming.ready);
    });

    test('reset clears the latch for the next side', () {
      final gate = _gate(dwell: Duration.zero);
      gate.update(_box(), at: t0);
      gate.reset();
      expect(gate.hasFired, isFalse);
      expect(gate.update(null, at: t0).framing, DocumentFraming.none);
    });

    test('progress runs 0 → 1 across the dwell', () {
      final gate = _gate(dwell: const Duration(seconds: 1));
      expect(gate.progress(t0), 0);
      gate.update(_box(), at: t0);
      expect(gate.progress(t0.add(const Duration(milliseconds: 500))), 0.5);
      expect(gate.progress(t0.add(const Duration(seconds: 2))), 1.0);
    });
  });
}
