import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/biometric_copy.dart';
import '../config/biometric_options.dart';
import '../config/copy_tokens.dart';
import '../config/kyc_config.dart';
import '../config/kyc_result.dart';
import '../config/result_copy.dart';
import '../config/scope.dart';
import '../config/selfie_upload_wait.dart';
import '../config/theme.dart';
import '../config/contact_recovery.dart';
import '../providers/kyc_state.dart';
import 'submitted_error_view.dart';
import 'submitted_result_view.dart';
import 'submitted_waiting_view.dart';
import '../widgets/check_badge.dart';
import '../providers/kyc_provider.dart';
import '../services/api_service.dart';
import '../services/kyc_error_mapper.dart';
import '../widgets/keep_links_sheet.dart';
import '../widgets/key_people_await_list.dart';
import '../widgets/presence_blocks.dart';
import '../providers/awaiting_people.dart';
import '../widgets/myaza_button.dart';

// ─── Submission status (local UI state) ──────────────────────────────────────

enum _SubmitStatus { submitting, success, error }

const String _kDefaultSuccessTitle = 'Verification Submitted!';
/// The default description depends on WHAT was submitted. A KYB applicant told
/// "your identity verification has been submitted" is being told about the
/// wrong thing: they submitted a company, and an address-only applicant
/// submitted a pin. Mirrors the web SDK's successDescription (scope map
/// included).
const Map<String, String> _kScopeDescriptions = {
  'address': "Your address verification has been submitted. "
      "You'll be notified of the result.",
  'biometric-authentication': "Your face check has been submitted. "
      "You'll be notified of the result.",
  'biometric-enrollment': "Your face enrolment has been submitted. "
      "You'll be notified of the result.",
  'questionnaire': "Your answers have been submitted. "
      "You'll be notified of the result.",
  'contact': "Your contact verification has been submitted. "
      "You'll be notified of the result.",
};

String _defaultSuccessDescription(bool isBusiness, String? scope) {
  final scoped = scope == null ? null : _kScopeDescriptions[scope];
  if (scoped != null) return scoped;
  return isBusiness
      ? "Your business verification has been submitted for review. "
          "You'll be notified of the result."
      : "Your identity verification has been submitted for review. "
          "You'll be notified of the result.";
}

String _fillTokens(String template, String firstName, String lastName) =>
    fillCopyTokens(template, firstName: firstName, lastName: lastName);

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

  /// The verdict, on a flow that WAITS for it in the app (a biometric
  /// re-authentication on the default delivery). Fires once, never on a wait
  /// that timed out. See [KYCResult].
  final void Function(KYCResult result)? onResult;

  const SubmittedScreen({
    super.key,
    this.onSubmitted,
    this.onError,
    this.onDone,
    this.onResult,
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

    // The biometric scopes hand over BEFORE the selfie upload lands (the
    // review is off, so nothing on the liveness screen gated on it): wait for
    // the upload's own record here, under the same loading screen. A failed
    // upload was already reported to onError by the screen that ran it.
    if (!ref.read(kycConfigProvider).showsSelfieReviewOption) {
      final upload = await awaitSelfieUpload(
        read: () {
          final s = ref.read(kYCNotifierProvider);
          return SelfieUploadSnapshot(selfieUpload: s.selfieUpload, selfieMediaId: s.mediaIds.selfie);
        },
        subscribe: (listener) {
          final sub = ref.listenManual<KYCState>(kYCNotifierProvider, (_, __) => listener());
          return sub.close;
        },
      );
      if (!mounted) return;
      if (upload is SelfieUploadFailed) {
        setState(() {
          _status = _SubmitStatus.error;
          _error = KYCError(code: 'upload_failed', message: upload.message);
        });
        return;
      }
    }

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

  /// Try Again after a failed selfie upload re-enters the liveness screen,
  /// whose mount resumes the interrupted upload and hands straight back here.
  /// The record is reset first so this screen waits for the NEW attempt rather
  /// than reading the old failure a second time.
  void _retryUpload() {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    notifier.setSelfieUpload(kIdleSelfieUpload);
    notifier.goToStep(KYCStep.liveness);
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
        : _defaultSuccessDescription(
            config.subjectType == 'business', configScope(config.scope));

    final scope = configScope(config.scope);
    final showDone = config.showsDoneButtonOption;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 480.0;
        // A flow that waits for its verdict (a biometric re-authentication, by
        // default) renders the result view from the FIRST build: it shows the
        // one loading screen through the upload wait, the submission and the
        // poll, then the verdict. onSubmitted has already fired by then.
        final Widget child = _status == _SubmitStatus.error
            ? ErrorView(
                error: _error!,
                onRetry: switch (_error!.code) {
                  'upload_failed' => _retryUpload,
                  'network_error' => _retry,
                  _ => null,
                },
                onClose: _close,
              )
            : config.waitsForResultOption
                ? SubmittedResultView(
                    verificationId: _status == _SubmitStatus.success
                        ? _submission!.verificationId
                        : null,
                    retryInfo: _retryInfo,
                    showDone: showDone,
                    onResult: widget.onResult,
                    onDone: _close,
                  )
                : _status == _SubmitStatus.submitting
                    ? Builder(builder: (_) {
                        final copy = describeWaiting(
                          scope: scope,
                          waitsForResult: false,
                          retry: _retryInfo,
                          override: config.biometricCopy.waiting,
                        );
                        return SubmittedWaitingView(
                          title: copy.title,
                          description: copy.description,
                          retrying: _retryInfo != null,
                        );
                      })
                    : _SuccessView(
                        submission: _submission!,
                        title: successTitle,
                        description: successDescription,
                        // KYB: per-person verification links for full-KYC key
                        // people, rendered so the applicant can send each one
                        // immediately.
                        invites: ref.watch(kYCNotifierProvider).keyPeopleInvites,
                        showDone: showDone,
                        onDone: _handleDone,
                      );
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: child,
        );
      },
    );
  }
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends ConsumerStatefulWidget {
  final KYCSubmission submission;
  final String title;
  final String description;
  final List<KeyPersonInvite> invites;

  /// The `doneButton` option: off for a host that dismisses the flow itself.
  final bool showDone;
  final void Function(bool hasOutstanding) onDone;

  const _SuccessView({
    required this.submission,
    required this.title,
    required this.description,
    this.invites = const [],
    this.showDone = true,
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
            if (ref.read(kycConfigProvider).addressCollection?.presenceEnabled == true &&
                ref.read(kYCNotifierProvider).address != null)
              const PresenceExpectations().animate(delay: 400.ms).fadeIn(duration: 350.ms),
            if (awaiting != null)
              KeyPeopleAwaitList(people: awaiting)
                  .animate(delay: 450.ms)
                  .fadeIn(duration: 350.ms)
            else if (invites.isNotEmpty)
              const KeyPeoplePending().animate(delay: 450.ms).fadeIn(duration: 350.ms),
            const SizedBox(height: MyazaSpacing.xl),
          ],
        ),
        if (widget.showDone)
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
              .moveY(begin: 8, end: 0, duration: 300.ms)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
