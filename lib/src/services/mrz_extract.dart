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
String sanitizeMrzLine(String raw) => raw
    .toUpperCase()
    // ML Kit's latin model (Android) reads OCR-B's '<' filler as guillemets:
    // '«' for a '<<' pair, '‹' for a single. Stripping them shortened every
    // filler run past what _fit tolerates, so an uploaded passport's MRZ never
    // read on Android (2026-09-15). The React Native extractor learned this
    // first; the check digits still decide.
    .replaceAll('«', '<<')
    .replaceAll('»', '<<')
    .replaceAll(RegExp('[‹›]'), '<')
    .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

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
  final pieces = <String>[];
  final candidates = <String>[];
  for (final raw in recognizedLines) {
    final line = sanitizeMrzLine(raw);
    if (line.isEmpty) continue;
    pieces.add(line);
    if (looksLikeMrzLine(line)) candidates.add(line);
  }
  if (candidates.isEmpty) return _fromFragments(pieces, now: now);

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

  return _fromFragments(pieces, now: now);
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
  // A filler run the recognizer miscounted. Android returns runs of '<' as
  // guillemets whose number does not match the fillers printed, so the mapped
  // run overshoots or falls short by many characters (a passport's first line
  // came back 53 wide, 2026-09-15). Trailing fillers are padding and carry no
  // data, so only they are removed or added.
  if (line.length > width && !line.substring(width).contains(_notFiller)) {
    return line.substring(0, width);
  }
  if (line.length < width && line.length >= width ~/ 2 && line.endsWith('<')) {
    return line.padRight(width, '<');
  }
  return null;
}

final _notFiller = RegExp('[^<]');

// ─── Split lines ──────────────────────────────────────────────────────────────
//
// On a high-resolution still, Android's recognizer can return ONE printed MRZ
// line as two text lines (2026-09-15: a passport's two-line MRZ band came back
// as three lines, and no single candidate had the right width). Joining runs of
// adjacent pieces back to line width recovers it; a wrong join is harmless for
// the reason at the top of this file.

/// The longest run of pieces one printed line is ever split into.
const _maxPiecesPerLine = 4;

/// Joined rows of [width], keyed by the index of the piece each one starts at.
Map<int, List<({int end, String text})>> _rowsByStart(
  List<String> pieces,
  int width,
) {
  final rows = <int, List<({int end, String text})>>{};
  for (var i = 0; i < pieces.length; i++) {
    var text = '';
    for (var j = i; j < pieces.length && j < i + _maxPiecesPerLine; j++) {
      text += pieces[j];
      // Generous: a joined row may carry an over-counted filler run _fit trims.
      if (text.length > width * 2) break;
      final fitted = _fit(text, width);
      if (fitted != null) (rows[i] ??= []).add((end: j, text: fitted));
    }
  }
  return rows;
}

/// Reads an MRZ out of lines the recognizer split: consecutive joined rows of
/// line width (TD3: two of 44, TD1: three of 30).
MrzScan? _fromFragments(List<String> pieces, {DateTime? now}) {
  final td3 = _rowsByStart(pieces, 44);
  for (final entry in td3.entries) {
    for (final a in entry.value) {
      for (final b in td3[a.end + 1] ?? const <({int end, String text})>[]) {
        final scan = parseMrz(a.text + b.text, now: now);
        if (scan != null) return scan;
      }
    }
  }
  final td1 = _rowsByStart(pieces, 30);
  for (final entry in td1.entries) {
    for (final a in entry.value) {
      for (final b in td1[a.end + 1] ?? const <({int end, String text})>[]) {
        for (final c in td1[b.end + 1] ?? const <({int end, String text})>[]) {
          final scan = parseMrz(a.text + b.text + c.text, now: now);
          if (scan != null) return scan;
        }
      }
    }
  }
  return null;
}
