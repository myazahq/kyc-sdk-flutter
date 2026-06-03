import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── Variants ─────────────────────────────────────────────────────────────────

enum MyazaButtonVariant { primary, outline, ghost, destructive }

// ─── Button ───────────────────────────────────────────────────────────────────

class MyazaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final MyazaButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final Widget? leadingIcon;

  const MyazaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = MyazaButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
  });

  // ── Convenience constructors ───────────────────────────────────────────────

  const MyazaButton.outline({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
  }) : variant = MyazaButtonVariant.outline;

  const MyazaButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
  }) : variant = MyazaButtonVariant.ghost;

  const MyazaButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
  }) : variant = MyazaButtonVariant.destructive;

  // ── Style helpers (context-aware) ──────────────────────────────────────────

  static const _radius = BorderRadius.all(Radius.circular(MyazaRadius.sm));

  Color _bg(MyazaColorScheme colors) => switch (variant) {
        MyazaButtonVariant.primary     => colors.primary,
        MyazaButtonVariant.destructive => MyazaColors.error,
        _                              => Colors.transparent,
      };

  Color _fg(MyazaColorScheme colors) => switch (variant) {
        MyazaButtonVariant.primary     => colors.onPrimary,
        MyazaButtonVariant.destructive => Colors.white,
        MyazaButtonVariant.outline     => colors.primary,
        MyazaButtonVariant.ghost       => colors.primary,
      };

  Color _disabledBg(MyazaColorScheme colors) => switch (variant) {
        MyazaButtonVariant.primary     => colors.primary.withValues(alpha: 0.5),
        MyazaButtonVariant.destructive => MyazaColors.error.withValues(alpha: 0.5),
        _                              => Colors.transparent,
      };

  BorderSide? _border(MyazaColorScheme colors) => switch (variant) {
        MyazaButtonVariant.outline =>
          BorderSide(color: colors.primary, width: 1.5),
        _ => null,
      };

  BorderSide? _disabledBorder(MyazaColorScheme colors) => switch (variant) {
        MyazaButtonVariant.outline =>
          BorderSide(color: colors.primary.withValues(alpha: 0.4), width: 1.5),
        _ => null,
      };

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;

    final isDisabled = onPressed == null || isLoading;
    final fg = _fg(colors);
    final effectiveFg = isDisabled ? fg.withValues(alpha: 0.5) : fg;
    final bg = _bg(colors);

    final shape = RoundedRectangleBorder(
      borderRadius: _radius,
      side: (isDisabled ? _disabledBorder(colors) : _border(colors)) ?? BorderSide.none,
    );

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: effectiveFg,
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  IconTheme(
                    data: IconThemeData(color: effectiveFg, size: 18),
                    child: leadingIcon!,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(label, style: text.button.copyWith(color: effectiveFg)),
              ],
            ),
    );

    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _disabledBg(colors);
        if (states.contains(WidgetState.pressed)) {
          return bg == Colors.transparent
              ? colors.primary.withValues(alpha: 0.06)
              : bg.withValues(alpha: 0.88);
        }
        return bg;
      }),
      foregroundColor: WidgetStateProperty.all(effectiveFg),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return fg.withValues(alpha: 0.08);
        }
        return null;
      }),
      shape: WidgetStateProperty.all(shape),
      elevation: WidgetStateProperty.all(0),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
      ),
      minimumSize: WidgetStateProperty.all(
        Size(fullWidth ? double.infinity : 0, MyazaSizing.buttonHeight),
      ),
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: MyazaSizing.buttonHeight,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: buttonStyle,
        child: child,
      ),
    );
  }
}
