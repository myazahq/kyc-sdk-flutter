import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A step's primary actions, held at the bottom edge of a viewport-filling
/// body. Mirrors the web SDK's StickyActions and the RN twin.
///
/// A step that carries a map or a street panorama fills a phone with a
/// surface that OWNS every touch: dragging it moves the map, never the page,
/// so on a small screen the Continue button beneath it could only be reached
/// by finding a strip of margin to scroll on. Holding the actions under a
/// bounded scroll view means the applicant never has to get past the map to
/// move on, and everything else still scrolls under them.
///
/// Needs a BOUNDED parent: the step must be in the sheet's fills-viewport set
/// (myaza_kyc_widget.dart), or the Expanded below has nothing to expand into.
class StickyActions extends StatelessWidget {
  final Widget body;
  final Widget actions;

  const StickyActions({super.key, required this.body, required this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
            child: body,
          ),
        ),
        // RN's footer: the hairline runs edge to edge (its negative margins
        // cancel the body's padding) and the buttons keep their gutter, with
        // `md` under them before the vendor mark. The body here sits inside
        // the sheet's `md` padding, so the footer is sized wider than its
        // slot by the same on each side and centred, which paints it out to
        // the sheet's edges; its height stays the actions' own.
        LayoutBuilder(
          builder: (context, constraints) => FractionallySizedBox(
            widthFactor:
                (constraints.maxWidth + 2 * MyazaSpacing.md) / constraints.maxWidth,
            child: Container(
              padding: const EdgeInsets.fromLTRB(MyazaSpacing.md,
                  MyazaSpacing.sm, MyazaSpacing.md, MyazaSpacing.md),
              decoration: BoxDecoration(
                color: colors.background,
                border:
                    Border(top: BorderSide(color: colors.border, width: 0.5)),
              ),
              child: actions,
            ),
          ),
        ),
      ],
    );
  }
}
