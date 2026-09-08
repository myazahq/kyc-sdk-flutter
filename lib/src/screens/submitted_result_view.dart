import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/biometric_copy.dart';
import '../config/kyc_result.dart';
import '../config/result_copy.dart';
import '../config/result_wait.dart';
import '../config/scope.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/myaza_button.dart';
import 'submitted_waiting_view.dart';

// ─── The result screen (a flow that waits for its verdict) ──────────────────
//
// A biometric re-authentication delivered in the flow ('both', the default, or
// 'app') is answered NOW or it is useless. This screen is mounted from the
// submitted screen's FIRST build and shows one loading screen through the
// selfie upload, the submission (`verificationId` is null until it lands) and
// the status poll, then the verdict, firing `onResult` once. The wait has a
// budget: past it the screen says so and the webhook remains the record,
// exactly as on every other flow. `showDone` is the `doneButton` option: off
// when the host app dismisses the flow itself from `onResult`. Mirrors the RN
// SubmittedResult.

class SubmittedResultView extends ConsumerStatefulWidget {
  final String? verificationId;
  final ({int attempt, int total})? retryInfo;
  final bool showDone;
  final void Function(KYCResult result)? onResult;
  final VoidCallback onDone;

  const SubmittedResultView({
    super.key,
    required this.verificationId,
    required this.retryInfo,
    required this.showDone,
    required this.onResult,
    required this.onDone,
  });

  @override
  ConsumerState<SubmittedResultView> createState() => _SubmittedResultViewState();
}

class _SubmittedResultViewState extends ConsumerState<SubmittedResultView> {
  VerificationOutcome? _outcome;
  String? _waitingOn;

  @override
  void initState() {
    super.initState();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant SubmittedResultView old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  // The wait is tied to the verification: it starts once, when the id lands.
  void _maybeStart() {
    final id = widget.verificationId;
    if (id == null || _waitingOn != null) return;
    _waitingOn = id;
    final api = ref.read(kYCNotifierProvider.notifier).api;
    awaitVerificationOutcome(
      // A failed read is not a verdict (config/result_wait.dart skips it).
      fetchStatus: () async {
        try {
          return await api.status(id);
        } catch (_) {
          return null;
        }
      },
    ).then((settled) {
      if (!mounted) return;
      setState(() => _outcome = settled);
      if (settled is SettledOutcome) {
        widget.onResult?.call(KYCResult(
          verificationId: id,
          status: settled.status,
          reason: settled.reason,
          reasonCode: settled.reasonCode,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final config = ref.watch(kycConfigProvider);
    // The org's own words for these screens, tokens filled (null = the defaults).
    final words = config.biometricCopy;
    if (outcome == null) {
      final copy = describeWaiting(
        scope: configScope(config.scope),
        waitsForResult: true,
        retry: widget.retryInfo,
        override: words.waiting,
      );
      return SubmittedWaitingView(
        title: copy.title,
        description: copy.description,
        retrying: widget.retryInfo != null,
      );
    }

    final copy = describeOutcome(outcome, verified: words.verified, declined: words.declined);
    final colors = context.myazaColors;
    final text = context.myazaText;
    final (bg, fg, icon) = switch (copy.tone) {
      ResultTone.success => (colors.successBg, MyazaColors.success, LucideIcons.check),
      ResultTone.error => (colors.errorBg, MyazaColors.error, LucideIcons.circleAlert),
      // The org's primary, as RN reads it: the brand constant ignored a
      // custom primaryColor on this one tone.
      ResultTone.info => (
          colors.primary.withValues(alpha: 0.08),
          colors.primary,
          LucideIcons.info,
        ),
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
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg,
                  border: Border.all(color: fg.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(icon, size: 44, color: fg),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1.0, 1.0),
                    duration: 450.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(copy.title, style: text.heading1.copyWith(height: 1.2), textAlign: TextAlign.center)
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: MyazaSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.lg),
              child: Text(copy.description, style: text.bodyMedium, textAlign: TextAlign.center)
                  .animate(delay: 320.ms)
                  .fadeIn(duration: 350.ms),
            ),
            const SizedBox(height: MyazaSpacing.xl),
          ],
        ),
        if (widget.showDone)
          MyazaButton(label: 'Done', onPressed: widget.onDone)
              .animate(delay: 600.ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 8, end: 0, duration: 300.ms)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
