import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../widgets/myaza_alert.dart';
import '../widgets/myaza_button.dart';

// ─── Submission status (local UI state) ──────────────────────────────────────

enum _SubmitStatus { submitting, success, error }

// ─── Submitted screen ─────────────────────────────────────────────────────────
//
// Replaces the old ProcessingScreen + ResultScreen pair. On mount, calls
// kycProvider.submitAsync() which POSTs to /api/kyc/verify. The server
// returns 202 with { verificationId, status: 'pending' } in ~200ms — the
// SDK's job ends there. Final result arrives via webhook to the org's
// backend.

class SubmittedScreen extends ConsumerStatefulWidget {
  /// Called once the verify request succeeds (202).
  final void Function(KYCSubmission submission)? onSubmitted;

  /// Called when the verify request fails (network, 401, 402, etc).
  final void Function(KYCError error)? onError;

  /// Called when the user taps Done after a successful submission, OR
  /// taps "Close" on the error screen. Closes the modal/sheet.
  final VoidCallback? onDone;

  const SubmittedScreen({
    super.key,
    this.onSubmitted,
    this.onError,
    this.onDone,
  });

  @override
  ConsumerState<SubmittedScreen> createState() => _SubmittedScreenState();
}

class _SubmittedScreenState extends ConsumerState<SubmittedScreen> {
  _SubmitStatus _status = _SubmitStatus.submitting;
  KYCSubmission? _submission;
  KYCError? _error;

  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  Future<void> _submit() async {
    if (_kicked || !mounted) return;
    _kicked = true;

    setState(() {
      _status = _SubmitStatus.submitting;
      _error = null;
    });

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final result = await notifier.submitAsync();
      if (!mounted) return;

      final config = ref.read(kycConfigProvider);
      final submission = KYCSubmission(
        verificationId: result.verificationId,
        status: result.status,
        metadata: {...?config.metadata},
        submittedAt: DateTime.now(),
      );

      setState(() {
        _status = _SubmitStatus.success;
        _submission = submission;
      });

      widget.onSubmitted?.call(submission);
    } on KYCApiException catch (e) {
      if (!mounted) return;
      final error = _mapToKycError(e);
      setState(() {
        _status = _SubmitStatus.error;
        _error = error;
      });
      widget.onError?.call(error);
    } catch (_) {
      if (!mounted) return;
      const error = KYCError(
        code: 'unknown',
        message: 'Something went wrong. Please try again.',
      );
      setState(() {
        _status = _SubmitStatus.error;
        _error = error;
      });
      widget.onError?.call(error);
    }
  }

  KYCError _mapToKycError(KYCApiException e) {
    return switch (e.error) {
      'insufficient_credits' => KYCError(
          code: 'insufficient_credits',
          message:
              'Organization credits exhausted. Contact your administrator.',
          details: e.details,
        ),
      'invalid_api_key' => KYCError(
          code: 'invalid_api_key',
          message: e.message ?? 'Invalid or revoked API key.',
        ),
      'id_type_not_allowed' => const KYCError(
          code: 'feature_disabled',
          message:
              "This ID type isn't enabled for your organization. Contact your administrator to request access.",
        ),
      'feature_disabled' => KYCError(
          code: 'feature_disabled',
          message: switch (e.details?['feature']) {
            'document_verification' =>
              'Document verification is currently disabled for your organization.',
            'gov_db_check' =>
              'Government database verification is currently disabled for your organization.',
            _ => e.message ??
                'This verification feature is currently disabled for your organization.',
          },
          details: e.details,
        ),
      'upload_failed' => KYCError(
          code: 'upload_failed',
          message: e.message ?? 'A file failed to upload. Please try again.',
        ),
      'timeout' || 'network_error' || 'connection_error' => const KYCError(
          code: 'network_error',
          message: 'Connection failed. Please try again.',
        ),
      _ => KYCError(
          code: 'unknown',
          message: e.message ?? 'Something went wrong. Please try again.',
        ),
    };
  }

  void _retry() {
    _kicked = false;
    _submit();
  }

  void _close() {
    widget.onDone?.call();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 480.0;
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: switch (_status) {
            _SubmitStatus.submitting => const _SubmittingView(),
            _SubmitStatus.success => _SuccessView(
                submission: _submission!,
                onDone: _close,
              ),
            _SubmitStatus.error => _ErrorView(
                error: _error!,
                onRetry: _error!.code == 'network_error' ? _retry : null,
                onClose: _close,
              ),
          },
        );
      },
    );
  }
}

// ─── Submitting view ──────────────────────────────────────────────────────────

class _SubmittingView extends StatelessWidget {
  const _SubmittingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: MyazaSpacing.xl),
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            color: colors.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: MyazaSpacing.lg),
        Text(
          'Submitting your verification…',
          style: text.heading3,
          textAlign: TextAlign.center,
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: MyazaSpacing.sm),
        Text(
          "This will only take a moment.",
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.xl),
      ],
    );
  }
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final KYCSubmission submission;
  final VoidCallback onDone;

  const _SuccessView({required this.submission, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: MyazaSpacing.xl),
            Center(
              child: _CheckBadge(colors: colors)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 450.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              'Your verification has\nbeen submitted!',
              style: text.heading1.copyWith(height: 1.2),
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: MyazaSpacing.sm),
            Text(
              "You'll be notified of the result.",
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
            const SizedBox(height: MyazaSpacing.xl),
          ],
        ),
        MyazaButton(label: 'Done', onPressed: onDone)
            .animate(delay: 600.ms)
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, end: 0, duration: 300.ms),
      ],
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final KYCError error;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  const _ErrorView({
    required this.error,
    required this.onClose,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final title = switch (error.code) {
      'insufficient_credits' => 'Credits Exhausted',
      'invalid_api_key' => 'Authentication Failed',
      'feature_disabled' => 'Verification Unavailable',
      'upload_failed' => 'Upload Failed',
      'network_error' => 'Connection Failed',
      _ => 'Submission Failed',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: MyazaSpacing.xl),
            Center(
              child: _ErrorBadge(colors: colors)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 450.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              title,
              style: text.heading1,
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: MyazaSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
              child: MyazaAlert(
                variant: MyazaAlertVariant.error,
                title: 'What happened',
                message: error.message,
              ),
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
          ],
        ),
        Row(
          children: [
            if (onRetry != null) ...[
              Expanded(
                child: MyazaButton.outline(
                  label: 'Try Again',
                  onPressed: onRetry,
                  leadingIcon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(width: MyazaSpacing.md),
            ],
            Expanded(
              child: MyazaButton(label: 'Close', onPressed: onClose),
            ),
          ],
        )
            .animate(delay: 420.ms)
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, end: 0, duration: 300.ms),
      ],
    );
  }
}

// ─── Verification ID card (copyable monospace) ───────────────────────────────

class _VerificationIdCard extends StatefulWidget {
  final String verificationId;
  final MyazaColorScheme colors;
  final MyazaThemeText text;

  const _VerificationIdCard({
    required this.verificationId,
    required this.colors,
    required this.text,
  });

  @override
  State<_VerificationIdCard> createState() => _VerificationIdCardState();
}

class _VerificationIdCardState extends State<_VerificationIdCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.verificationId));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        border: Border.all(color: widget.colors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: MyazaSpacing.md,
        vertical: MyazaSpacing.md,
      ),
    );
  }
}

// ─── Check badge ──────────────────────────────────────────────────────────────

class _CheckBadge extends StatelessWidget {
  final MyazaColorScheme colors;

  const _CheckBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.successBg,
        border: Border.all(
          color: MyazaColors.success.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 44,
        color: MyazaColors.success,
      ),
    );
  }
}

// ─── Error badge ──────────────────────────────────────────────────────────────

class _ErrorBadge extends StatelessWidget {
  final MyazaColorScheme colors;

  const _ErrorBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.errorBg,
        border: Border.all(
          color: MyazaColors.error.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.error_outline_rounded,
        size: 44,
        color: MyazaColors.error,
      ),
    );
  }
}
