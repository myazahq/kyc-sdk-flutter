import 'package:flutter/material.dart';

import '../config/theme.dart';

// ─── Variant ──────────────────────────────────────────────────────────────────

enum MyazaAlertVariant { error, success, warning, info }

extension _MyazaAlertVariantStyle on MyazaAlertVariant {
  Color get accentColor => switch (this) {
        MyazaAlertVariant.error   => MyazaColors.error,
        MyazaAlertVariant.success => MyazaColors.success,
        MyazaAlertVariant.warning => MyazaColors.warning,
        MyazaAlertVariant.info    => MyazaColors.info,
      };

  Color bgColor(MyazaColorScheme colors) => switch (this) {
        MyazaAlertVariant.error   => colors.errorBg,
        MyazaAlertVariant.success => colors.successBg,
        MyazaAlertVariant.warning => colors.warningBg,
        MyazaAlertVariant.info    => colors.infoBg,
      };

  IconData get icon => switch (this) {
        MyazaAlertVariant.error   => Icons.error_outline_rounded,
        MyazaAlertVariant.success => Icons.check_circle_outline_rounded,
        MyazaAlertVariant.warning => Icons.warning_amber_rounded,
        MyazaAlertVariant.info    => Icons.info_outline_rounded,
      };
}

// ─── Alert ────────────────────────────────────────────────────────────────────

class MyazaAlert extends StatelessWidget {
  final String title;
  final String? message;
  final MyazaAlertVariant variant;
  final VoidCallback? onDismiss;

  const MyazaAlert({
    super.key,
    required this.title,
    this.message,
    this.variant = MyazaAlertVariant.info,
    this.onDismiss,
  });

  const MyazaAlert.error({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = MyazaAlertVariant.error;

  const MyazaAlert.success({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = MyazaAlertVariant.success;

  const MyazaAlert.warning({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = MyazaAlertVariant.warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    final accent = variant.accentColor;
    final bg     = variant.bgColor(colors);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Colored left accent bar ──────────────────────────────────────
            Container(width: 4, color: accent),

            // ── Content ──────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyazaSpacing.md,
                  vertical: MyazaSpacing.sm + 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(variant.icon, size: 18, color: accent),
                    const SizedBox(width: MyazaSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: text.label.copyWith(color: accent),
                          ),
                          if (message != null && message!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message!,
                              style: text.bodySmall.copyWith(
                                color: accent.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onDismiss != null) ...[
                      const SizedBox(width: MyazaSpacing.sm),
                      GestureDetector(
                        onTap: onDismiss,
                        child: Icon(Icons.close, size: 16, color: accent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
