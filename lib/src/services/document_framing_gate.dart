import 'document_detection.dart';

// ─── Auto-capture framing gate ────────────────────────────────────────────────
//
// Decides when a detected shape is (a) actually the expected ID document and
// (b) framed well enough to shoot. Pure logic, no camera or widget dependency,
// so the thresholds are unit-tested rather than tuned by trial on a device.
//
// Four conditions, each earning its place:
//   • SHAPE — the detected aspect must match the expected document. The edge
//     detector will happily segment a book, a receipt or a laptop; aspect is
//     what tells an ID card apart from them, so without this it captures
//     anything rectangular.
//   • SIZE — big enough that the crop keeps the detail OCR and MRZ need, but
//     NOT so big that it's overflowing the frame.
//   • MARGIN — every edge clear of the frame border, so all four corners are
//     in shot with a little space around them. A document cropped flush to a
//     corner loses characters, and OCR reads the edges worst.
//   • STABILITY — held steady for a dwell, so the shot isn't taken mid-move.
//     This is what stops the blurry captures that make auto-capture feel worse
//     than a manual shutter.

/// What to actually tell the user. The gate rejects for several distinct
/// reasons, and collapsing them into one "align your ID" message left people
/// stuck: the commonest failure is holding the document TOO CLOSE, where the
/// instinct is to move nearer still.
enum DocumentHint {
  /// Nothing found yet — neutral prompt.
  searching,

  /// The frame is too dark for detection to work.
  moreLight,

  /// Something is there but it isn't the expected document.
  wrongDocument,

  /// Detected, but too small in frame.
  moveCloser,

  /// Detected, but overflowing — corners are cut. THIS is the one users can't
  /// guess.
  moveBack,

  /// Right size, but not centred.
  centre,

  /// Passport only: the page is readable but the machine-readable strip along
  /// the bottom is not in frame. Auto-capture waits for it (it is the chip's
  /// key and the proof the page is a passport), so saying "move closer" here —
  /// which is what a generic hint did — sends the user the wrong way.
  showMrz,

  /// Framed correctly, running out the stability dwell.
  holdStill,

  /// Fired.
  captured,
}

/// The gate's verdict for one frame: the visual state plus the instruction.
class DocumentGuidance {
  final DocumentFraming framing;
  final DocumentHint hint;

  const DocumentGuidance(this.framing, this.hint);
}

enum DocumentFraming {
  /// Nothing document-shaped in the frame.
  none,

  /// Something detected, but it isn't the right shape for this document.
  wrongShape,

  /// Right shape, but too small / too large / too close to an edge.
  adjust,

  /// Well framed, waiting out the stability dwell.
  holding,

  /// Well framed and stable — take the photo.
  ready,
}

class DocumentFramingGate {
  /// Expected width/height of the document (1.586 for ID cards, 1.42 for a
  /// passport page).
  final double expectedAspect;

  /// How far the detected aspect may stray, as a fraction of [expectedAspect].
  /// Generous enough for perspective, tight enough to reject a book or A4 page.
  final double aspectTolerance;

  /// Minimum share of the frame the document must fill.
  final double minArea;

  /// Maximum share — beyond this the document is overflowing and corners are
  /// probably already cut.
  final double maxArea;

  /// Minimum gap between every document edge and the frame edge.
  final double minEdgeMargin;

  /// Maximum distance the document's centre may sit from the frame's centre.
  final double maxOffCentre;

  /// Minimum detector confidence to consider a detection at all.
  final double minConfidence;

  /// How long the framing must hold before firing.
  final Duration dwell;

  /// Mean frame luma below which we ask for more light. Deliberately low —
  /// a false "add light" on a legibly-lit document is more annoying than a
  /// slightly dim capture.
  final double minBrightness;

  DocumentFramingGate({
    required this.expectedAspect,
    this.aspectTolerance = 0.28,
    this.minArea = 0.22,
    this.maxArea = 0.88,
    this.minEdgeMargin = 0.02,
    this.maxOffCentre = 0.14,
    this.minConfidence = 0.5,
    this.dwell = const Duration(milliseconds: 900),
    this.minBrightness = 0.22,
  });

  DateTime? _heldSince;
  bool _fired = false;

  /// True once [DocumentFraming.ready] has been reported, so the caller can't
  /// double-fire while the capture is in flight.
  bool get hasFired => _fired;

  /// Progress through the stability dwell, 0..1 — drives the UI's scan ring.
  double progress(DateTime now) {
    final since = _heldSince;
    if (since == null) return 0;
    final elapsed = now.difference(since).inMilliseconds;
    final total = dwell.inMilliseconds;
    if (total <= 0) return 1;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// True when the detected shape is plausibly this document type.
  bool matchesShape(DocumentBox box) {
    final delta = (box.aspectRatio - expectedAspect).abs();
    return delta <= expectedAspect * aspectTolerance;
  }

  /// Feeds one frame and returns both the visual state and what to tell the
  /// user. [brightness] is the frame's mean luma (0..1).
  DocumentGuidance update(
    DocumentBox? box, {
    DateTime? at,
    double brightness = 0.5,
  }) {
    final now = at ?? DateTime.now();
    if (_fired) {
      return const DocumentGuidance(
          DocumentFraming.ready, DocumentHint.captured);
    }

    if (box == null || box.confidence < minConfidence) {
      _heldSince = null;
      // Nothing found AND the frame is dark: light is the likely cause, and
      // it's actionable, so say that instead of a neutral "looking…".
      final hint = brightness < minBrightness
          ? DocumentHint.moreLight
          : DocumentHint.searching;
      return DocumentGuidance(DocumentFraming.none, hint);
    }

    // Shape first: a wrong-shaped object is not "adjust your framing", it's the
    // wrong object, and the UI should say so rather than inviting the user to
    // move a book around.
    if (!matchesShape(box)) {
      _heldSince = null;
      return const DocumentGuidance(
          DocumentFraming.wrongShape, DocumentHint.wrongDocument);
    }

    // Order matters: report the reason the user must act on FIRST. Too-close is
    // checked before centring because an overflowing document is usually also
    // off-centre, and "move back" is the instruction that actually helps.
    DocumentHint? problem;
    if (box.area > maxArea || box.edgeMargin < minEdgeMargin) {
      problem = DocumentHint.moveBack;
    } else if (box.area < minArea) {
      problem = DocumentHint.moveCloser;
    } else if (box.offCentre > maxOffCentre) {
      problem = DocumentHint.centre;
    }

    if (problem != null) {
      // Reset the dwell: a document that drifts out and back has not been held
      // steady, and shooting on re-entry is exactly when a blurry frame slips
      // through.
      _heldSince = null;
      return DocumentGuidance(DocumentFraming.adjust, problem);
    }

    // Well framed but dim — the shot would be readable-ish, but OCR does much
    // better with light, so ask before firing rather than after failing.
    if (brightness < minBrightness) {
      _heldSince = null;
      return const DocumentGuidance(
          DocumentFraming.adjust, DocumentHint.moreLight);
    }

    _heldSince ??= now;
    if (now.difference(_heldSince!) >= dwell) {
      _fired = true;
      return const DocumentGuidance(
          DocumentFraming.ready, DocumentHint.captured);
    }
    return const DocumentGuidance(
        DocumentFraming.holding, DocumentHint.holdStill);
  }

  /// Clears the dwell and the fired latch — call when moving to the next side
  /// or after a retake.
  void reset() {
    _heldSince = null;
    _fired = false;
  }
}
