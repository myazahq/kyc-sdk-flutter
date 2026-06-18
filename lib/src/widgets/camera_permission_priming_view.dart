import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import 'myaza_button.dart';

/// "Allow camera access" priming screen, shown right before the native OS camera
/// permission prompt (mirrors Stripe Identity). It sets the user's expectation
/// that the system prompt is coming so they're primed to accept it — the actual
/// permission request only fires once they tap "Grant access".
///
/// Distinct from [CameraPermissionView], which is shown *after* a denial.
class CameraPermissionPrimingView extends StatelessWidget {
  final String message;

  /// Fires when the user taps "Grant access" — triggers the real camera start.
  final VoidCallback onGrant;

  const CameraPermissionPrimingView({
    super.key,
    required this.message,
    required this.onGrant,
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
                  color: colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.camera,
                  size: 36,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              'Allow camera access',
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
            MyazaButton(label: 'Grant access', onPressed: onGrant),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}
