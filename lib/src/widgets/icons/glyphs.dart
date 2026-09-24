import 'app_icon.dart' show MyazaIconData;

/// Glyphs Hugeicons does not carry, drawn in the set's own stroke language.
///
/// Kept to the strict minimum: every other icon comes from the set, and this
/// file exists only where the set has no equivalent at all. Mirrors the web
/// SDK's `components/icons/glyphs.ts`, path for path, so the two draw one
/// shape.

const Map<String, String> _stroke = {
  'stroke': 'currentColor',
  'strokeWidth': '1.5',
  'strokeLinecap': 'round',
  'strokeLinejoin': 'round',
};

/// A LONG left arrow — a full-width shaft with a small head.
///
/// Hugeicons has no such glyph. Its longest one-way left arrow is
/// `strokeRoundedArrowLeft02`, whose shaft spans 13.5 of the 24-unit viewBox;
/// the rest are shorter, bare chevrons, or arrows into a vertical bar. The back
/// control drew Lucide's `MoveLeft` before the icon migration, whose shaft is
/// 20 units, so moving to the set visibly shortened it.
///
/// The geometry is Lucide's, inset to sit on the same optical margins as its
/// Hugeicons siblings (they start at ~3.5 rather than Lucide's 2), and the
/// stroke attributes are copied from the set so weight and joins match exactly.
const MyazaIconData kLongArrowLeft = [
  ['path', {'key': '0', 'd': 'M20.5 12H3.5', ..._stroke}],
  ['path', {'key': '1', 'd': 'M8 7.5L3.5 12L8 16.5', ..._stroke}],
];
