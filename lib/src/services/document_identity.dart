import 'document_framing_gate.dart' show DocumentHint;
import 'document_type_signals.dart';

// ─── Document identity ────────────────────────────────────────────────────────
//
// "Is the thing in frame the document the user picked?" — answered from
// recognized text, and used by BOTH platforms so a capture has to clear the
// same bar on Android and iOS.
//
// Geometry alone cannot answer it: an aspect ratio cannot tell a passport from
// a driver's licence, so iOS's rectangle detector would happily shoot the wrong
// document. Text alone cannot answer it either — the word "passport" appears in
// prose, in code, and on any screen showing KYC documentation, which is exactly
// how a laptop screen full of text once identified as a passport and fired.
//
// So identity is deliberately strict about the one document that can prove
// itself: an MRZ. Only travel documents carry one, it is always on the page a
// passport capture is supposed to frame, and it validates by check digit — so
// for passports the machine-readable zone, not the printed word, is the proof.

/// Whether the frame has been positively identified, and what to tell the user
/// when it hasn't.
class DocumentIdentity {
  final bool identified;

  /// Meaningful only when [identified] is false.
  final DocumentHint hint;

  const DocumentIdentity(this.identified, this.hint);

  static const searching = DocumentIdentity(false, DocumentHint.searching);
  static const ok = DocumentIdentity(true, DocumentHint.holdStill);
}

/// ID types whose page always carries a machine-readable zone. For these the
/// MRZ is required before a capture can fire — see the note above.
bool documentCarriesMrz(String idType) => idType == 'passport';

/// Verifies that [lines] identify the document the user picked.
///
/// [requireValidMrz] is set when the chip step needs the MRZ as a key, which
/// additionally demands a CHECK-DIGIT-VALID read ([hasValidMrz]) rather than
/// merely MRZ-shaped text — that is what makes one scan enough for NFC.
/// [mrzAlreadyCaptured] means the key is already stored from an earlier frame,
/// which satisfies that requirement without re-reading it.
DocumentIdentity verifyDocumentIdentity(
  List<String> lines, {
  required String country,
  required String idType,
  bool requireValidMrz = false,
  bool hasValidMrz = false,
  bool mrzAlreadyCaptured = false,
  double minConfidence = 0.34,
  double wrongTypeMargin = 0.34,
}) {
  if (lines.isEmpty) return DocumentIdentity.searching;

  // ── The MRZ rule ──────────────────────────────────────────────────────────
  // For an MRZ-bearing document the zone must actually be in frame. This is the
  // check that rejects a screen, a printout or a page that merely mentions the
  // word, and it is why the passport path cannot be fooled by prose.
  if (documentCarriesMrz(idType) && !hasValidMrz && !hasMrzLines(lines)) {
    // Say WHICH problem it is. Text that already reads as the expected document
    // is most likely the real thing with the strip cropped off the bottom edge
    // — the commonest framing mistake on a passport — and telling that user
    // "wrong document" sends them hunting for a different one. Text that
    // identifies as nothing keeps the blunter message.
    final looksRight =
        detectDocumentType(lines, country).type == idType;
    return DocumentIdentity(
      false,
      looksRight ? DocumentHint.showMrz : DocumentHint.wrongDocument,
    );
  }

  // ── Keyword identity ──────────────────────────────────────────────────────
  // Only where signals exist: most Global Documents countries have no curated
  // list, and there we must not block on a check we cannot perform.
  if (hasDocumentSignals(country, idType)) {
    final match = detectDocumentType(lines, country);
    final expected = match.type == idType ? match.confidence : 0.0;

    // Reading clearly as a DIFFERENT document — the server would reject this
    // after upload as `document_type_mismatch`, so say so now.
    if (match.type != null &&
        match.type != idType &&
        match.confidence >= expected + wrongTypeMargin) {
      return const DocumentIdentity(false, DocumentHint.wrongDocument);
    }

    // Two independent keyword hits identify the document, whatever the length
    // of its synonym list.
    //
    // Confidence alone is a ratio, so a type with a thorough list is HARDER to
    // recognise than a sparse one: Nigeria's voter card lists eight synonyms
    // and so needed three hits to clear the bar, while a passport needed two —
    // one of which its MRZ supplies for free. On a busy holographic card, in
    // hand, that is the difference between firing at once and hunting. The
    // wrong-type check above still uses the ratio, where comparing two types
    // on one scale is exactly what it is for.
    final identifiedByCount = match.type == idType && match.matched >= 2;
    if (!identifiedByCount && expected < minConfidence) {
      return DocumentIdentity(
        false,
        lines.length < 5 ? DocumentHint.searching : DocumentHint.moveCloser,
      );
    }
  }

  // ── Chip key ──────────────────────────────────────────────────────────────
  // Firing before the MRZ validates means the chip step has to scan the same
  // document a second time, which is the whole reason this gate exists.
  if (requireValidMrz && !hasValidMrz && !mrzAlreadyCaptured) {
    // The document is identified; only the strip is missing. "Move closer"
    // would push the user to crop it off entirely.
    return const DocumentIdentity(false, DocumentHint.showMrz);
  }

  return DocumentIdentity.ok;
}
