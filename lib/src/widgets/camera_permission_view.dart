import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import 'myaza_button.dart';

/// Friendly screen shown when the OS camera permission is denied/blocked.
/// Explains that camera access is required and how to re-enable it, with an
/// "Open Settings" action and a "Try Again" retry. Mirrors the web SDK's
/// permission-denied screen. The owning screen reports the typed
/// `camera_permission_denied` error to `onError`.
class CameraPermissionView extends StatelessWidget {
  final String message;
  final VoidCallback onOpenSettings;

  /// "Try Again" re-checks the permission. Pass null to hide the button — on
  /// iOS the only way to grant access is via Settings (which relaunches the
  /// app), so re-checking in place can never succeed and the button is omitted.
  final VoidCallback? onRetry;

  /// Optional extra action (e.g. "Upload a photo instead" on document capture).
  final Widget? secondaryAction;

  const CameraPermissionView({
    super.key,
    required this.message,
    required this.onOpenSettings,
    this.onRetry,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: MyazaSpacing.md,
          vertical: MyazaSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: MyazaColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.cameraOff,
                  size: 38,
                  color: MyazaColors.error,
                ),
              ),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              'Camera access needed',
              style: text.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyazaSpacing.xs),
            Text(
              message,
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyazaSpacing.lg),
            MyazaButton(label: 'Open Settings', onPressed: onOpenSettings),
            if (onRetry != null) ...[
              const SizedBox(height: MyazaSpacing.sm),
              MyazaButton.outline(label: 'Try Again', onPressed: onRetry),
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: MyazaSpacing.sm),
              secondaryAction!,
            ],
          ],
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}
