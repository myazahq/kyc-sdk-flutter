import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// One icon from the Hugeicons Stroke Rounded set.
///
/// The set ships icons as SVG path data rather than as [IconData], so this is
/// deliberately NOT a font glyph: anything that stored an icon in a field or
/// returned one from a helper holds this type instead.
typedef MyazaIconData = List<List<dynamic>>;

/// The stroke every icon in the SDK is drawn at.
///
/// 1.6 is the dashboard's and the web SDK's weight. An icon means the same
/// thing and looks the same wherever a customer meets it, so the number lives
/// here once rather than at 200 call sites.
const double kMyazaIconStrokeWidth = 1.6;

/// The SDK's one icon widget.
///
/// The icon is the first POSITIONAL argument, exactly like Flutter's own
/// [Icon], so a call site reads the same either way and nothing had to be
/// re-shaped when the set changed underneath it.
///
/// A null [size] or [color] inherits from the surrounding `IconTheme`, which is
/// what [Icon] does and what most of this SDK relies on. A null [icon] holds
/// its space rather than collapsing, also like [Icon]: a row of optional icons
/// must not shift when one of them is absent.
class MyazaIcon extends StatelessWidget {
  const MyazaIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final MyazaIconData? icon;
  final double? size;
  final Color? color;

  /// Announced by screen readers. Icons are decorative unless they carry
  /// meaning no nearby text repeats, in which case they need this.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = size ?? IconTheme.of(context).size ?? 24.0;
    final data = icon;

    // The drawing is pinned to [resolved] and CENTRED, never stretched to the
    // parent.
    //
    // This mirrors what Flutter's own [Icon] does, and it has to be explicit
    // here: `Icon` draws a font glyph, which is a fixed size whatever box it is
    // handed, while this draws an SVG, which fills the box it is given. A
    // `Container(width: 56, height: 56, child: ...)` passes TIGHT constraints,
    // so without the inner SizedBox under a Center the glyph silently grows to
    // 56 and the icon looks about twice the size the call site asked for.
    final Widget glyph = Center(
      child: SizedBox.square(
        dimension: resolved,
        child: data == null
            ? const SizedBox.shrink()
            : HugeIcon(
                icon: data,
                size: resolved,
                color: color,
                strokeWidth: kMyazaIconStrokeWidth,
              ),
      ),
    );

    final sized = SizedBox.square(dimension: resolved, child: glyph);
    final label = semanticLabel;
    if (label == null) return sized;
    return Semantics(label: label, child: sized);
  }
}
