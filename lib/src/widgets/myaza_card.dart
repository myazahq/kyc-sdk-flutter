import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── Card ─────────────────────────────────────────────────────────────────────

class MyazaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final bool hasBorder;
  final double? borderRadius;

  const MyazaCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.hasBorder = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final radius = BorderRadius.circular(borderRadius ?? MyazaRadius.md);

    final decoration = BoxDecoration(
      color: backgroundColor ?? colors.background,
      borderRadius: radius,
      border: hasBorder ? Border.all(color: colors.border) : null,
    );

    if (onTap == null) {
      return Container(
        decoration: decoration,
        padding: padding ?? const EdgeInsets.all(MyazaSpacing.md),
        child: child,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: colors.primary.withValues(alpha: 0.06),
        highlightColor: colors.primary.withValues(alpha: 0.04),
        child: Ink(
          decoration: decoration,
          padding: padding ?? const EdgeInsets.all(MyazaSpacing.md),
          child: child,
        ),
      ),
    );
  }
}
