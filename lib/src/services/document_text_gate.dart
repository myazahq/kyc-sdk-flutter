import 'dart:ui' show Rect;

import 'document_framing_gate.dart' show DocumentFraming, DocumentGuidance;
import 'document_framing_gate.dart' show DocumentHint;
import 'document_identity.dart';

// ─── Text-based auto-capture gate (Android) ───────────────────────────────────
//
// iOS auto-captures off Apple Vision's rectangle detector (document EDGES).
// Android has no frame-by-frame rectangle detector in ML Kit, so auto-capture
// rides on-device TEXT recognition instead.
//
// The two platforms nonetheless answer the SAME two questions before firing, so
// a capture clears the same bar on both:
//
//   • IDENTITY — is this the document the user picked? Shared with iOS via
//     verifyDocumentIdentity (document_identity.dart).
//   • FRAMING — is it presented like a document? iOS measures the detected
//     rectangle; here we measure the region the recognized text occupies, which
//     is the only geometry ML Kit gives us. It is a proxy for the document's
//     extent, not its edges, so the thresholds below are deliberately loose —
//     they are here to reject text sprawling across the whole frame (a screen,
//     a page of prose) or a document too far away to read, not to fine-tune
//     composition.
//   • STABILITY — held steady for a dwell, so the shot isn't taken mid-move.
//
// Pure logic (no camera/ML dependency) so the thresholds are testable.

class DocumentTextGate {
  /// Minimum recognized text lines to treat the frame as showing a document.
  final int minLines;

  /// Smallest share of the frame the text region may cover. Below this the
  /// document is too far away for OCR to read it well.
  final double minTextArea;

  /// Largest share. Text covering nearly the whole frame is not a document held
  /// up to the camera — it is a screen, a book, or a wall of print.
  final double maxTextArea;

  /// How far the text region's centre may sit from the frame's centre, as a
  /// share of the frame. Generous: text is rarely centred on a document.
  final double maxOffCentre;

  /// How long the framing must hold before firing — the stability window that
  /// stops mid-move (blurry) captures.
  final Duration dwell;

  DocumentTextGate({
    this.minLines = 5,
    this.minTextArea = 0.06,
    this.maxTextArea = 0.82,
    this.maxOffCentre = 0.30,
    this.dwell = const Duration(milliseconds: 700),
  });

  DateTime? _heldSince;
  bool _fired = false;

  bool get hasFired => _fired;

  /// Progress through the stability dwell, 0..1 — drives the UI's scan ring.
  double progress(DateTime now) {
    final since = _heldSince;
    if (since == null) return 0;
    final total = dwell.inMilliseconds;
    if (total <= 0) return 1;
    return (now.difference(since).inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Feeds one frame's recognized [lines] and, when the platform provides it,
  /// the normalised (0..1) bounding box of all recognized text.
  DocumentGuidance update(
    List<String> lines, {
    required String country,
    required String idType,
    Rect? textBounds,
    bool requireMrz = false,
    bool hasValidMrz = false,
    bool mrzAlreadyCaptured = false,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    if (_fired) {
      return const DocumentGuidance(
          DocumentFraming.ready, DocumentHint.captured);
    }

    // ── Identity ────────────────────────────────────────────────────────────
    final identity = verifyDocumentIdentity(
      lines,
      country: country,
      idType: idType,
      requireValidMrz: requireMrz,
      hasValidMrz: hasValidMrz,
      mrzAlreadyCaptured: mrzAlreadyCaptured,
    );
    if (!identity.identified) {
      _heldSince = null;
      return DocumentGuidance(
        identity.hint == DocumentHint.wrongDocument
            ? DocumentFraming.wrongShape
            : DocumentFraming.none,
        identity.hint,
      );
    }

    // A check-digit-valid MRZ read from THIS frame is conclusive: only a travel
    // document carries one, and it only validates when legible — so it proves
    // identity and readability at once, and the shot need not wait out a dwell.
    // (A merely STORED MRZ does not qualify: see mrzAlreadyCaptured, or every
    // retake would fire on its first frame.)
    if (hasValidMrz) {
      _fired = true;
      return const DocumentGuidance(
          DocumentFraming.ready, DocumentHint.holdStill);
    }

    // ── Framing ─────────────────────────────────────────────────────────────
    final framingHint = _framingProblem(textBounds, lines.length);
    if (framingHint != null) {
      _heldSince = null;
      return DocumentGuidance(DocumentFraming.adjust, framingHint);
    }

    // ── Stability ───────────────────────────────────────────────────────────
    _heldSince ??= now;
    if (now.difference(_heldSince!) >= dwell) {
      _fired = true;
      return const DocumentGuidance(
          DocumentFraming.ready, DocumentHint.holdStill);
    }
    return const DocumentGuidance(
        DocumentFraming.holding, DocumentHint.holdStill);
  }

  /// Why the text region isn't acceptably framed, or null when it is.
  DocumentHint? _framingProblem(Rect? bounds, int lineCount) {
    if (bounds == null) {
      // No geometry from this platform — fall back to text density alone.
      return lineCount < minLines ? DocumentHint.moveCloser : null;
    }
    final area = (bounds.width * bounds.height).clamp(0.0, 1.0);
    if (area < minTextArea) return DocumentHint.moveCloser;
    if (area > maxTextArea) return DocumentHint.moveBack;

    final offCentreX = (bounds.center.dx - 0.5).abs();
    final offCentreY = (bounds.center.dy - 0.5).abs();
    if (offCentreX > maxOffCentre || offCentreY > maxOffCentre) {
      return DocumentHint.centre;
    }
    return null;
  }

  /// Clears the latch so the next side (or a retake) starts a fresh dwell.
  void reset() {
    _heldSince = null;
    _fired = false;
  }
}
