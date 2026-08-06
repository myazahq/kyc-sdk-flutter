import 'package:flutter/material.dart';

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

Future<T?> showMyazaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final theme = Theme.of(context);
  final colors = context.myazaColors;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: colors.background,
    isScrollControlled: isScrollControlled,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(MyazaRadius.xl)),
    ),
    builder: (sheetContext) => Theme(
      data: theme,
      child: Builder(builder: builder),
    ),
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
