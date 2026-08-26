import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../config/contact_recovery.dart';
import 'submitted_error_view.dart';
import '../widgets/check_badge.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../services/kyc_error_mapper.dart';
import '../widgets/keep_links_sheet.dart';
import '../widgets/key_people_await_list.dart';
import '../providers/awaiting_people.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_pulse_loader.dart';

// ─── Submission status (local UI state) ──────────────────────────────────────

enum _SubmitStatus { submitting, success, error }

const String _kDefaultSuccessTitle = 'Verification Submitted!';
/// The default description depends on WHAT was submitted. A KYB applicant told
/// "your identity verification has been submitted" is being told about the
/// wrong thing: they submitted a company. Mirrors the web SDK's
/// successDescription.
String _defaultSuccessDescription(bool isBusiness) => isBusiness
    ? "Your business verification has been submitted for review. "
        "You'll be notified of the result."
    : "Your identity verification has been submitted for review. "
        "You'll be notified of the result.";

/// Replaces `{firstName}` / `{lastName}` tokens with the user's data (or '').
String _fillTokens(String template, String firstName, String lastName) =>
    template
        .replaceAll('{firstName}', firstName)
        .replaceAll('{lastName}', lastName)
        .trim();

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

  /// Set while a transient failure is being retried — drives the "Reconnecting…
  /// retrying (n/total)" copy under the spinner.
  ({int attempt, int total})? _retryInfo;

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
      _retryInfo = null;
    });

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final result = await notifier.submitAsync(
        onRetry: (attempt, total) {
          if (mounted) {
            setState(() => _retryInfo = (attempt: attempt, total: total));
          }
        },
      );
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
        _retryInfo = null;
      });

      widget.onSubmitted?.call(submission);
    } on KYCApiException catch (e) {
      if (!mounted) return;
      // A refusal over stale contact proofs is recoverable in-flow: clear the
      // dead tokens and walk back to the contact step, which routes straight
      // back here once re-verified (see config/contact_recovery.dart).
      final channels = expiredContactChannels(e);
      if (channels.isNotEmpty) {
        final notifier = ref.read(kYCNotifierProvider.notifier);
        notifier.clearContactProofs(channels);
        notifier.goToStep(contactStepFor(channels.first));
        return;
      }
      // Retries (if any) are exhausted — surface a typed error.
      final error = mapToKycError(e, context: ErrorContext.verify);
      setState(() {
        _status = _SubmitStatus.error;
        _error = error;
        _retryInfo = null;
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
        _retryInfo = null;
      });
      widget.onError?.call(error);
    }
  }

  void _retry() {
    _kicked = false;
    _submit();
  }

  void _close() {
    widget.onDone?.call();
  }

  /// Done, with a catch: if key people still owe a check, their invite links
  /// die with this screen — so offer the session's web page (where the links
  /// stay live) before letting the flow close. Workflow opt-out:
  /// `keyPeopleLinkRecovery: false` (on by default).
  /// [hasOutstanding] comes from the SERVER's settled list where there is one,
  /// falling back to "we minted invites" before it arrives. Offering to keep
  /// links alive when everybody has already verified is a prompt about nothing.
  void _handleDone(bool hasOutstanding) {
    final kycState = ref.read(kYCNotifierProvider);
    final config = ref.read(kycConfigProvider);
    final url = kycState.sessionUrl;
    if (hasOutstanding && url != null && config.keyPeopleLinkRecovery) {
      showKeepLinksSheet(context, url: url, onDone: _close);
      return;
    }
    _close();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(kycConfigProvider);
    final firstName = config.userData?.firstName ?? '';
    final lastName = config.userData?.lastName ?? '';
    final successTitle = config.success?.title != null
        ? _fillTokens(config.success!.title!, firstName, lastName)
        : _kDefaultSuccessTitle;
    final successDescription = config.success?.description != null
        ? _fillTokens(config.success!.description!, firstName, lastName)
        : _defaultSuccessDescription(config.subjectType == 'business');

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 480.0;
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: switch (_status) {
            _SubmitStatus.submitting => _SubmittingView(retryInfo: _retryInfo),
            _SubmitStatus.success => _SuccessView(
                submission: _submission!,
                title: successTitle,
                description: successDescription,
                // KYB: per-person verification links for full-KYC key people
                // — rendered so the applicant can send each one immediately.
                invites: ref.watch(kYCNotifierProvider).keyPeopleInvites,
                onDone: _handleDone,
              ),
            _SubmitStatus.error => ErrorView(
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
  /// Non-null while a transient failure is being retried.
  final ({int attempt, int total})? retryInfo;

  const _SubmittingView({this.retryInfo});

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final retrying = retryInfo != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: MyazaSpacing.xl),
        const MyazaPulseLoader(),
        const SizedBox(height: MyazaSpacing.lg),
        Text(
          retrying ? 'Reconnecting…' : 'Submitting your verification…',
          style: text.heading3,
          textAlign: TextAlign.center,
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: MyazaSpacing.sm),
        Text(
          retrying
              ? 'Connection issue — retrying (${retryInfo!.attempt}/${retryInfo!.total})…'
              : 'Please wait a moment.',
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MyazaSpacing.xl),
      ],
    );
  }
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends ConsumerStatefulWidget {
  final KYCSubmission submission;
  final String title;
  final String description;
  final List<KeyPersonInvite> invites;
  final void Function(bool hasOutstanding) onDone;

  const _SuccessView({
    required this.submission,
    required this.title,
    required this.description,
    this.invites = const [],
    required this.onDone,
  });

  @override
  ConsumerState<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends ConsumerState<_SuccessView> {
  AwaitingPeopleController? _awaiting;

  @override
  void initState() {
    super.initState();
    // WHO the application is waiting on, from the server. The invite links
    // above are the applicant's own list; registry discovery runs after
    // submission and can add directors nobody listed, so this is the only
    // account of the people that is actually complete.
    final sessionId = ref.read(kYCNotifierProvider).sessionId;
    // KYB only: an individual verification has no key people to wait on.
    if (sessionId == null ||
        ref.read(kycConfigProvider).subjectType != 'business') {
      return;
    }
    _awaiting = AwaitingPeopleController(
      api: ref.read(kYCNotifierProvider.notifier).api,
      sessionId: sessionId,
    )..addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _awaiting?..removeListener(_onUpdate)..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final title = widget.title;
    final description = widget.description;
    final invites = widget.invites;
    final awaiting = _awaiting?.people;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: MyazaSpacing.xl),
            const Center(child: CheckBadge()),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              title,
              style: text.heading1.copyWith(height: 1.2),
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: MyazaSpacing.sm),
            Text(
              description,
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
            // ONE list, from the SERVER. The applicant's own draft invites used
            // to render above this with their own copy/share buttons, so the
            // same people appeared twice and a reader had to hold both lists to
            // answer "who still owes me something". The link lives on the row.
            //
            // Absent until the server says its list is settled: a list shown
            // earlier is one director short, permanently. While it is coming,
            // say so — a blank where a list is about to appear reads as
            // "nobody needs to verify", which for a KYB application is the
            // opposite of true.
            if (awaiting != null)
              KeyPeopleAwaitList(people: awaiting)
                  .animate(delay: 450.ms)
                  .fadeIn(duration: 350.ms)
            else if (invites.isNotEmpty)
              const KeyPeoplePending().animate(delay: 450.ms).fadeIn(duration: 350.ms),
            const SizedBox(height: MyazaSpacing.xl),
          ],
        ),
        MyazaButton(
          label: 'Done',
          onPressed: () => widget.onDone(
            awaiting != null
                ? awaiting.any((p) => p.stillOwes)
                : invites.isNotEmpty,
          ),
        )
            .animate(delay: 600.ms)
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, end: 0, duration: 300.ms),
      ],
    );
  }
}
