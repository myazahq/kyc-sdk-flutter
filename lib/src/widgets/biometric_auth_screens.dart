part of 'myaza_biometric_auth.dart';

// ─── Face re-auth screens ────────────────────────────────────────────────────
//
// The intro, the authenticating wait and the result, split out of the entry
// file (200-line rule). A part so they stay private to it.

class _Intro extends StatelessWidget {
  final VoidCallback onStart;
  const _Intro({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(children: [
      const SizedBox(height: MyazaSpacing.lg),
      _Glyph(icon: LucideIcons.user, tint: colors.primary),
      const SizedBox(height: MyazaSpacing.lg),
      Text(
        "We'll take a quick face check to confirm your identity. No documents needed.",
        style: text.body.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: MyazaSpacing.xl),
      MyazaButton(label: 'Start', onPressed: onStart),
    ]);
  }
}

class _Authenticating extends StatelessWidget {
  const _Authenticating();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(children: [
      const SizedBox(height: MyazaSpacing.xl * 2),
      CircularProgressIndicator(color: colors.primary),
      const SizedBox(height: MyazaSpacing.lg),
      Text("Verifying it's you…",
          style: text.body.copyWith(fontWeight: FontWeight.w600)),
      Text('This only takes a moment.',
          style: text.bodySmall.copyWith(color: colors.textSecondary)),
    ]);
  }
}

class _Result extends StatelessWidget {
  final BiometricAuthResponse? result;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  const _Result({
    required this.result,
    required this.errorMessage,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final ok = result?.authenticated == true;
    final failed = result != null && !ok;
    final tint = ok ? MyazaColors.success : MyazaColors.error;
    final heading = ok
        ? "You're verified"
        : failed
            ? "Couldn't verify you"
            : 'Something went wrong';
    final detail = ok
        ? "We confirmed it's really you."
        : failed
            ? "We couldn't confirm it's you. Make sure your face is clear and well lit, then try again."
            : errorMessage ?? 'Something went wrong. Please try again.';
    return Column(children: [
      const SizedBox(height: MyazaSpacing.lg),
      // The web's result: a check, or the alert circle the flow's own verdict
      // screen uses (never a bare X), under a heading-font title.
      _Glyph(icon: ok ? LucideIcons.check : LucideIcons.circleAlert, tint: tint),
      const SizedBox(height: MyazaSpacing.lg),
      Text(heading, style: text.heading2, textAlign: TextAlign.center),
      const SizedBox(height: MyazaSpacing.xs),
      Text(detail,
          style: text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center),
      const SizedBox(height: MyazaSpacing.xl),
      if (ok)
        MyazaButton(label: 'Done', onPressed: onClose)
      else ...[
        MyazaButton(label: 'Try again', onPressed: onRetry),
        TextButton(
          onPressed: onClose,
          child: Text('Close',
              style: text.body.copyWith(color: colors.textSecondary)),
        ),
      ],
    ]);
  }
}

class _Glyph extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _Glyph({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint.withValues(alpha: 0.1),
        ),
        child: Icon(icon, size: 36, color: tint),
      );
}
