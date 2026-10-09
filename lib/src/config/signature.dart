import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

// A signature drawn on screen, as the strokes the server draws the image from.
//
// The SDK sends POINTS, never a picture: the server renders one image for the
// web, React Native and Flutter SDKs alike, so all three produce the same file.
// MIRROR of the web SDK's lib/signature.ts and of the server's
// `signatureProblem` (kyc-core src/lib/signature/render.ts) for the one rule
// the applicant needs to hear about before submitting: a tap or a dot is not a
// signature. Keep the ratio in lockstep with the server's.

/// Ink, as a share of the pad's shorter side, below which nothing was signed.
const double kSignatureMinInkRatio = 0.6;

/// The server refuses more than this; a pad stops recording well before it.
const int kSignatureMaxPoints = 20000;

class SignatureDrawing {
  const SignatureDrawing({required this.strokes, required this.width, required this.height});

  final List<List<Offset>> strokes;

  /// The pad's size, in the same units as the points.
  final double width;
  final double height;

  double get inkLength {
    var total = 0.0;
    for (final stroke in strokes) {
      for (var i = 1; i < stroke.length; i++) {
        total += (stroke[i] - stroke[i - 1]).distance;
      }
    }
    return total;
  }

  int get pointCount => strokes.fold(0, (sum, stroke) => sum + stroke.length);

  /// Whether there is enough ink to keep as a signature.
  bool get hasSignature => inkLength >= kSignatureMinInkRatio * math.min(width, height);

  /// The wire body: points rounded to one decimal, empty strokes dropped.
  Map<String, dynamic> toJson() {
    double r(double n) => (n * 10).round() / 10;
    return {
      'width': r(width),
      'height': r(height),
      'strokes': [
        for (final stroke in strokes)
          if (stroke.isNotEmpty)
            [
              for (final p in stroke) {'x': r(p.dx), 'y': r(p.dy)},
            ],
      ],
    };
  }
}

/// Fit strokes to a pad that changed size (expanded, shrunk, or rotated), so
/// nothing already signed ends up outside the box. One uniform scale, so the
/// signature keeps its shape; growing only the height leaves it where it is.
/// Returns the SAME list when nothing needs to move.
List<List<Offset>> rescaleStrokes(List<List<Offset>> strokes, Size from, Size to) {
  if (from.width <= 0 || from.height <= 0 || to.width <= 0 || to.height <= 0) return strokes;
  final scale = math.min(to.width / from.width, to.height / from.height);
  if ((scale - 1).abs() < 0.01) return strokes;
  return [
    for (final stroke in strokes) [for (final p in stroke) p * scale],
  ];
}
