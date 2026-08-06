import 'mrz_parser.dart';

// ─── MRZ extraction from OCR output ───────────────────────────────────────────
//
// Turns whatever the text recognizer returns for a frame into an MRZ candidate.
// OCR is messy: it may return the two MRZ lines separately, merge them into one,
// split one across two, or interleave them with the rest of the photo page. So
// rather than trusting layout, we sanitize every line, keep the MRZ-shaped ones
// (`<`-dense, right length), and try each plausible grouping.
//
// Correctness comes from the check digits in [parseMrz], not from this file —
// anything that survives the grouping still has to validate, so a wrong guess
// is harmless.

/// Strips everything that can't appear in an MRZ and upper-cases the rest.
String sanitizeMrzLine(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9<]'), '');

/// True when a line looks like part of an MRZ rather than ordinary page text.
/// MRZ lines are filler-padded, so `<` density is the strongest signal.
bool looksLikeMrzLine(String sanitized) {
  if (sanitized.length < 28) return false;
  final fillers = '<'.allMatches(sanitized).length;
  return fillers >= 2;
}

/// Attempts to read an MRZ out of one frame's recognized lines.
/// Returns null when this frame doesn't carry a complete, valid MRZ.
MrzScan? extractMrz(List<String> recognizedLines, {DateTime? now}) {
  final candidates = <String>[];
  for (final raw in recognizedLines) {
    final line = sanitizeMrzLine(raw);
    if (looksLikeMrzLine(line)) candidates.add(line);
  }
  if (candidates.isEmpty) return null;

  // 1) A single line already holding the whole MRZ (some recognizers merge).
  for (final line in candidates) {
    if (line.length == 88 || line.length == 90) {
      final scan = parseMrz(line, now: now);
      if (scan != null) return scan;
    }
  }

  // 2) TD3 — two adjacent 44-char lines.
  for (var i = 0; i + 1 < candidates.length; i++) {
    final a = _fit(candidates[i], 44);
    final b = _fit(candidates[i + 1], 44);
    if (a == null || b == null) continue;
    final scan = parseMrz(a + b, now: now);
    if (scan != null) return scan;
  }

  // 3) TD1 — three adjacent 30-char lines.
  for (var i = 0; i + 2 < candidates.length; i++) {
    final a = _fit(candidates[i], 30);
    final b = _fit(candidates[i + 1], 30);
    final c = _fit(candidates[i + 2], 30);
    if (a == null || b == null || c == null) continue;
    final scan = parseMrz(a + b + c, now: now);
    if (scan != null) return scan;
  }

  return null;
}

/// Coerces a candidate to exactly [width]. Recognizers commonly clip a trailing
/// filler or bolt on a stray glyph from the page edge, so a near-miss is worth
/// one attempt — the check digits reject it if the guess was wrong.
String? _fit(String line, int width) {
  if (line.length == width) return line;
  // Too short by a filler or two: MRZ lines are '<'-padded on the right.
  if (line.length >= width - 2 && line.length < width) {
    return line.padRight(width, '<');
  }
  // Too long: drop trailing noise.
  if (line.length > width && line.length <= width + 3) {
    return line.substring(0, width);
  }
  return null;
}
