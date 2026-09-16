import '../services/api_service.dart' show DocumentCaptureCheckResult;

// ─── Document capture check ───────────────────────────────────────────────────
//
// After a document side uploads, the server reads it with the SAME detectors it
// later decides the verification with: a readable face on the printed photo
// (the front, and only when the workflow compares the selfie with that photo)
// and a readable barcode (the side that carries one, for documents whose
// details are read from a barcode). A miss is caught here, while the applicant
// is still holding the document, instead of as a decline once they have gone.
//
// A NOTICE, NEVER A GATE. A detector can miss, so "Continue anyway" is always
// offered, and anything the server could not answer (null, an error, a
// timeout) reads as no problem at all.
//
// Mirrored in the web and React Native SDKs: keep the copy word for word.

const String kCaptureCheckTitle = 'Check your photos';
const String kCaptureCheckContinueAnyway = 'Continue anyway';

/// What the server could not find on a side.
enum CaptureProblemKind { noFace, noBarcode }

/// One finding: which side (`front` | `back`), and what was missing on it.
class CaptureProblem {
  final String side;
  final CaptureProblemKind kind;

  const CaptureProblem(this.side, this.kind);

  @override
  bool operator ==(Object other) =>
      other is CaptureProblem && other.side == side && other.kind == kind;

  @override
  int get hashCode => Object.hash(side, kind);

  @override
  String toString() => 'CaptureProblem($side, ${kind.name})';
}

/// Report order: the front before the back, since retaking the front starts
/// both sides over.
const List<String> _kSides = ['front', 'back'];

/// The retakes to ask for, front before back and, on each side, a missing face
/// before a missing barcode. Each finding appears once, however many answers
/// carried it.
List<CaptureProblem> captureCheckProblems(
  List<DocumentCaptureCheckResult?> results,
) {
  final answered = results.whereType<DocumentCaptureCheckResult>().toList();
  bool missing(String side, bool? Function(DocumentCaptureCheckResult) flag) =>
      // `== false` on purpose: `true` is fine, and `null` means "not
      // applicable" or "could not look". Neither may ask anyone to retake.
      answered.any((r) => r.side == side && flag(r) == false);

  return [
    for (final side in _kSides) ...[
      if (missing(side, (r) => r.face))
        CaptureProblem(side, CaptureProblemKind.noFace),
      if (missing(side, (r) => r.barcode))
        CaptureProblem(side, CaptureProblemKind.noBarcode),
    ],
  ];
}

/// The sides that need a retake, in report order, each once.
List<String> captureProblemSides(List<CaptureProblem> problems) => [
      for (final side in _kSides)
        if (problems.any((p) => p.side == side)) side,
    ];

/// What to tell the applicant. Each line names the cause and the fix.
String captureProblemMessage(CaptureProblemKind kind) => switch (kind) {
      CaptureProblemKind.noFace =>
        "We couldn't see the face in the photo on the front of your ID. "
            'Retake it in good light, with the ID out of any plastic cover and '
            'no glare over the photo.',
      CaptureProblemKind.noBarcode =>
        "We couldn't read the barcode on the back of your ID. Retake it with "
            'the ID out of any plastic cover, flat, filling the frame and with '
            'no glare over the barcode.',
    };

/// The retake button for [side]. An upload-only flow picked its photos rather
/// than taking them, so it says "Replace", as the review thumbnails do.
String captureRetakeLabel(String side, {required bool uploadOnly}) =>
    '${uploadOnly ? 'Replace' : 'Retake'} ${side == 'back' ? 'back' : 'front'}';
