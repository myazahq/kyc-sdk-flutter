import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/screen_corners.dart';
import '../config/theme.dart';

// ─── Themed bottom sheet ──────────────────────────────────────────────────────
//
// The SDK injects its palette as a ThemeExtension around the flow's CONTENT,
// which lives inside a modal route. A sheet opened from there is a SIBLING
// route, not a descendant — so `Theme.of` there has no MyazaColorScheme and
// `context.myazaColors` silently falls back to the LIGHT scheme (a white sheet
// over a dark flow). Passing the current ThemeData explicitly into the sheet
// re-establishes the extension no matter where the route lands.
//
// Always open SDK sheets through this helper rather than showModalBottomSheet.
//
// The panel FLOATS: detached from the screen edges by a tight 8px on the
// left, right and bottom (the bottom clearing the home indicator when that is
// larger), with all four corners rounded — a card presented over the flow,
// not a drawer welded to the edge. Mirrors the RN SDK's FloatingSheet; the
// gap is deliberately small so the float reads as intent rather than margin.

/// The tight gap that detaches the floating card from the screen edges.
/// Public so one-off sheets that cannot route through [showMyazaSheet]
/// (the Android NFC reading sheet) still share the exact geometry.
const double kMyazaSheetInset = 8;

/// The square-cornered-screen fallback for [myazaSheetRadius].
const double kMyazaSheetRadius = 38;

/// The grab handle, so its position can be asserted rather than eyeballed.
const Key kMyazaSheetHandleKey = Key('myaza-sheet-handle');

/// The float's corner radius is PRESENTATION GRAMMAR, not branding — and it is
/// computed the way Apple computes nested corners: CONCENTRIC with the
/// display, i.e. the device's own corner radius minus the gap, so the sheet's
/// curve runs parallel to the phone's. Square-cornered screens have no curve
/// to be concentric with, so they keep the share-sheet look instead. Never the
/// brand-scaled [MyazaRadius] tokens: an org whose buttons are 4px square
/// should not get a squared-off bottom sheet. Mirrors the RN FloatingSheet.
double myazaSheetRadius(BuildContext context) {
  final screen = displayCornerRadius(context);
  return screen > 0
      ? math.max(screen - kMyazaSheetInset, 16.0)
      : kMyazaSheetRadius;
}

/// The grab handle and close button every sheet wears.
///
/// Flutter's sheet is drag-dismissible by default, but nothing on screen SAID
/// so: the panel arrived with no handle and no close, so the only way out was
/// a backdrop tap nobody had been told about. The RN SDK's FloatingSheet has
/// carried this header for a while and the two are the same product.
///
/// Deliberately handle + close ONLY, no title: a sheet's own heading belongs to
/// its body, sitting tight under the handle the way the system sheets do it.
///
/// The header is also the drag surface, which comes free here for the reason it
/// does not in RN: it is the one part of the panel that never scrolls, so a
/// downward swipe on it reaches the sheet instead of the list.
class _MyazaSheetHeader extends StatelessWidget {
  const _MyazaSheetHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // Concentric corners put the panel's edge further in, so the button follows
    // the curve rather than sitting on it. Weighted to sit INSIDE the arc: at
    // the top right the corner is still turning, so a control set by the flat
    // edge reads as crowding it.
    final inset = (myazaSheetRadius(context) * 0.42).clamp(16.0, 26.0);

    // A STACK, not a row. In a row the handle is centred against the tallest
    // child, so the close button's 44pt touch box was setting how far down the
    // panel the handle sat: 8 of padding plus half of 44 put it ~30 from the
    // lip. Overlapping them lets the button keep its full target while the
    // handle rides where a grabber belongs, just under the edge.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              // Keyed so a test can measure where it sits. The layout that put
              // it halfway down the panel read as correct in review.
              key: kMyazaSheetHandleKey,
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(MyazaRadius.full),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            // Pushed down as well as in. The button's own 44pt box already
            // holds the icon 22 off its edges, so on the right the icon sits
            // inset+22 from the panel while on the top it sat at 22 flat: the
            // control hung off the corner instead of tucking into it. This
            // brings the two closer without paying the full inset in header
            // height.
            child: Padding(
              padding: EdgeInsets.only(top: (inset - 6).clamp(6.0, 16.0)),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close',
                // Kept at the 44pt minimum. The box may overlap the handle's
                // line because a touch target is allowed to reach past what it
                // draws; shrinking it to tidy the layout would not be.
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon:
                    Icon(LucideIcons.x, size: 18, color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<T?> showMyazaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,

  /// Off for a sheet that draws its own dismiss affordance, so the two do not
  /// stack into a panel with two close buttons.
  bool showHeader = true,
}) {
  final theme = Theme.of(context);
  final colors = context.myazaColors;

  // A tall sheet must stop BELOW the status bar. `isScrollControlled` lets one
  // grow to the full screen, and a full-height panel on a notched phone runs
  // its own header under the Dynamic Island: the close button was behind the
  // island and the title sat in the status bar. The same 8 that detaches the
  // card at the sides and bottom detaches it at the top.
  final media = MediaQuery.of(context);
  final maxHeight = media.size.height - media.padding.top - kMyazaSheetInset;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    constraints: BoxConstraints(maxHeight: math.max(maxHeight, 120)),
    builder: (sheetContext) {
      // The CARD sits low, like the system share sheet: a tight 8px off the
      // screen edge, with the home indicator riding ON the card. No inner
      // foot either, deliberately — a scrolling body runs all the way to the
      // lip and is CLIPPED by the curve, content sliding under the rounded
      // edge the way the system does it.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          kMyazaSheetInset,
          0,
          kMyazaSheetInset,
          kMyazaSheetInset,
        ),
        child: Material(
          color: colors.background,
          clipBehavior: Clip.antiAlias,
          // A hairline edge, so the panel separates from the flow behind it
          // instead of blending into it on a dark theme. `shape` rather than
          // `borderRadius`: Material takes one or the other, and only shape
          // carries a side.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(myazaSheetRadius(sheetContext)),
            side: BorderSide(color: colors.border.withValues(alpha: 0.6)),
          ),
          // The card floats clear of the home indicator, so a body's own
          // SafeArea must not pad for it a second time.
          child: MediaQuery.removePadding(
            context: sheetContext,
            removeBottom: true,
            child: Theme(
              data: theme,
              child: showHeader
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _MyazaSheetHeader(),
                        Flexible(child: Builder(builder: builder)),
                      ],
                    )
                  : Builder(builder: builder),
            ),
          ),
        ),
      );
    },
  );
}

/// Date picker carrying the SDK palette. `showDatePicker` builds a Material
/// dialog off `ColorScheme`, not our extension, so without this it renders in
/// the host app's colours — a light dialog over a dark flow.
Future<DateTime?> showMyazaDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final theme = Theme.of(context);
  final colors = context.myazaColors;
  // The flow's theme is derived from the consumer's appearance overrides, so
  // `theme.brightness` tracks the HOST app, not the flow. Read the flow's own
  // background instead.
  final isDark = colors.background.computeLuminance() < 0.5;

  final base = isDark ? const ColorScheme.dark() : const ColorScheme.light();

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (dialogContext, child) => Theme(
      data: theme.copyWith(
        colorScheme: base.copyWith(
          primary: colors.primary,
          onPrimary: colors.background,
          surface: colors.background,
          onSurface: colors.textDark,
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
