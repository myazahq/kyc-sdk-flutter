import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/document_capture_methods.dart';
import '../config/kyc_config.dart';
import '../config/proof_of_address.dart';
import '../config/appearance_scheme.dart';
import '../config/theme.dart';
import '../liveness/liveness_types.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/step_order.dart';
import '../providers/theme_provider.dart';
import '../utils/portrait_lock.dart';
import 'kyc_flow_scope.dart';

export 'kyc_flow_scope.dart' show kycFlowOverrides;
import '../screens/applicant_role_screen.dart';
import '../screens/business_details_screen.dart';
import '../screens/business_documents_screen.dart';
import '../config/supporting_documents.dart';
import '../screens/supporting_documents_screen.dart';
import '../screens/business_key_people_screen.dart';
import '../screens/consent_screen.dart';
import '../screens/contact_verification_channel.dart';
import '../screens/contact_verification_screen.dart';
import '../screens/country_select_screen.dart';
import '../screens/document_capture_screen.dart';
import '../screens/id_input_screen.dart';
import '../screens/id_type_screen.dart';
import '../screens/nfc_screen.dart';
import '../config/address_flow.dart';
import '../providers/address_step_order.dart';
import '../screens/address/address_entrance_step.dart';
import '../screens/address/address_pin_step.dart';
import '../screens/address/address_review_step.dart';
import '../screens/address/address_search_step.dart';
import '../screens/proof_of_address_screen.dart';
import '../screens/questionnaire_screen.dart';
import 'multi_id_progress.dart';
import 'myaza_pulse_loader.dart';
import 'workflow_gate.dart';
import '../screens/liveness_screen.dart';
import '../screens/submitted_screen.dart';
import '../utils/resolve_url.dart';
import 'kyc_bottom_sheet.dart';
import 'sandbox_banner.dart';
import 'myaza_button.dart';
import '../config/kyc_result.dart';
import '../services/model_readiness.dart';
import 'icons/icons.dart';

// ─── Step metadata ────────────────────────────────────────────────────────────

class _StepMeta {
  final String title;
  final String? description;

  const _StepMeta(this.title, [this.description]);
}

const Map<KYCStep, _StepMeta> _kStepMeta = {
  // Consent has no header title — the screen renders its own greeting.
  KYCStep.consent: _StepMeta(''),
  KYCStep.idType: _StepMeta(
    'Select ID Type',
    "Choose the type of identification document you'd like to use.",
  ),
  // documentCapture title/description are computed dynamically below.
  KYCStep.documentCapture: _StepMeta('Capture Document'),
  // idInput title is computed dynamically from selectedIdType; this is the
  // fallback before one is picked.
  KYCStep.idInput: _StepMeta(
    'Enter your ID number',
    'We’ll check this against the official record.',
  ),
  KYCStep.liveness: _StepMeta(
    'Face Verification',
    'Follow the on-screen instructions',
  ),
  // Optional steps (populated with real copy by their workstreams). Present
  // here so the `_kStepMeta[step]!` lookup never misses once a step is enabled.
  // Wording matches the web and React Native SDKs so the same flow reads
  // identically on every platform.
  KYCStep.contactEmail: _StepMeta(
    'Verify your email',
    "We'll send a one-time code to confirm this email belongs to you.",
  ),
  KYCStep.contactPhone: _StepMeta(
    'Verify your phone number',
    "We'll send a one-time code to confirm this number belongs to you.",
  ),
  KYCStep.countrySelect: _StepMeta(
    'Where was your ID issued?',
    'Choose the country that issued your identity document.',
  ),
  KYCStep.nfc: _StepMeta(
    'Scan Document Chip',
    'Hold your document to the back of your phone.',
  ),
  // proofOfAddress description is computed dynamically from maxAgeDays.
  KYCStep.proofOfAddress: _StepMeta('Proof of address'),
  // The pin and review steps re-title themselves for a KYB premises, and the
  // flow's first step drops its title entirely while the presence primer is
  // showing — see the build overrides below.
  KYCStep.addressSearch: _StepMeta(
    'Find your address',
    'Search it, use your current location, or place a pin on the map.',
  ),
  KYCStep.addressCollection: _StepMeta(
    'Is the pin on your building?',
    'Drag the map until the pin sits exactly on it. You can add details for whoever needs to find it.',
  ),
  KYCStep.addressEntrance: _StepMeta(
    'Show the entrance',
    'A picture of the gate or front door makes the address findable.',
  ),
  KYCStep.addressReview: _StepMeta(
    'Confirm your address',
    'Check everything is right before you continue.',
  ),
  KYCStep.supportingDocuments: _StepMeta(
    'Supporting documents',
    'Upload the documents below so we can keep them on file. Required documents are marked with *.',
  ),
  KYCStep.questionnaire: _StepMeta(
    'A Few More Questions',
    'Please answer the following to complete your verification.',
  ),
  KYCStep.businessDetails: _StepMeta(
    'Business Details',
    'Provide your business registration details for verification against the official registry.',
  ),
  KYCStep.businessKeyPeople: _StepMeta(
    'Directors & Owners',
    "List the company's directors and owners. Each person will receive a link "
        'to verify their identity; a shareholder that is itself a company is '
        'recorded rather than asked to verify.',
  ),
  KYCStep.businessDocuments: _StepMeta(
    'Business documents',
    'Upload the supporting documents for your business. Each one must clearly show the registered business name and registration number. Required documents are marked with *.',
  ),
  KYCStep.applicantRole: _StepMeta(
    'Now verify your own identity',
    'Tell us your role at the business, then verify your identity with a government-issued ID.',
  ),
  // submitted has no title — the screen owns its layout.
  KYCStep.submitted: _StepMeta(''),
};


/// Maps the appearance's initial theme to a ThemeMode. Null appearance/theme
/// and the explicit `system` value both follow the device setting.
// The flow's opening theme mode and its ProviderScope overrides both live in
// kyc_flow_scope.dart, so the biometric host can mount the same scope without
// importing this file (which imports it — see that file's header).

// ─── Public entry points ──────────────────────────────────────────────────────

/// Static launcher — shows the KYC flow as a full-screen modal bottom sheet.
///
/// The environment (and base URL) is derived automatically from the API key
/// prefix — `pk_live_…` → production, `pk_test_…` → sandbox, `pk_dev_…` →
/// development. There is no `environment` parameter.
///
/// ```dart
/// MyazaKYC.show(
///   context: context,
///   config: MyazaKYCConfig(apiKey: 'pk_live_…', country: 'NG'),
///   onSubmit: (s) => print('Submitted: ${s.verificationId}'),
///   onError:  (e) => print('Error: ${e.code} — ${e.message}'),
/// );
/// ```
class MyazaKYC {
  MyazaKYC._();

  static Future<void> show({
    required BuildContext context,
    required MyazaKYCConfig config,
    void Function(KYCSubmission)? onSubmit,
    void Function(KYCError)? onError,
    VoidCallback? onClose,
    /// The verdict, on a flow that waits for it in the app (a biometric
    /// re-authentication on the default delivery). See [KYCResult].
    void Function(KYCResult)? onResult,
  }) async {
    // Fail loud on an invalid key prefix before presenting anything (throws
    // ArgumentError with a clear message).
    detectEnvironment(config.apiKey);

    // Resolve-before-mount: a workflow-driven flow is resolved first (behind a
    // loading barrier), then merged over the props (flow wins). On failure the
    // gate surfaces the error and we don't open the flow.
    var effectiveConfig = config;
    ServerSdkConfig? preloaded;
    if (config.workflowId != null && config.workflowId!.trim().isNotEmpty) {
      final result = await resolveWorkflowBeforeMount(context, config, onError);
      if (result == null) return;
      effectiveConfig = result.config;
      preloaded = result.serverConfig;
    }
    if (!context.mounted) return;

    // `country` is optional on the config so a workflow mount doesn't have to
    // invent one — the resolved flow supplies it above. THIS is where that becomes
    // a guarantee: everything downstream reads `effectiveCountry`, which treats a
    // country as always present, so a config that reaches the flow without one
    // would surface as an empty ID-type list rather than a stated problem.
    //
    // Only reachable by misconfiguration: no `country` AND no `workflowId`, or a
    // resolved flow that somehow carries neither (publish rejects a country-less
    // KYC draft, and a KYB flow's country comes from its business block).
    if ((effectiveConfig.country ?? '').trim().isEmpty) {
      onError?.call(const KYCError(
        code: 'unknown',
        message:
            'No country configured. Pass `country`, or a `workflowId` whose '
            'published flow carries one.',
      ));
      return;
    }

    // Shape + type from the RESOLVED appearance (so a workflow's branding wins
    // over props). Applied here, before the flow builds, because both are
    // module-level scales read during build — see MyazaRadius.applyScale.
    MyazaRadius.applyScale(effectiveConfig.appearance?.borderRadius);
    applyBrandFonts(
      body: effectiveConfig.appearance?.fontFamily,
      heading: effectiveConfig.appearance?.headingFontFamily,
    );

    final overrides = _overridesFor(effectiveConfig, preloaded);

    // Android: push a full-screen page modal.
    // iOS / other: show a draggable bottom sheet.
    if (Platform.isAndroid) {
      return Navigator.of(context, rootNavigator: true)
          .push<void>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (ctx) => ProviderScope(
                overrides: overrides,
                child: _KycFlowWidget(
                  isFullScreen: true,
                  onSubmit: onSubmit,
                  onError: onError,
                  onClose: onClose,
                  onResult: onResult,
                ),
              ),
            ),
          )
          .then((_) => onClose?.call());
    }

    // When the consumer disables close, the sheet can't be dragged down or
    // dismissed by tapping the barrier — only a programmatic pop closes it.
    final allowDismiss = !effectiveConfig.disableClose;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: allowDismiss,
      isDismissible: allowDismiss,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (ctx) => ProviderScope(
        overrides: overrides,
        child: _KycFlowWidget(
          isFullScreen: false,
          onSubmit: onSubmit,
          onError: onError,
          onClose: onClose,
          onResult: onResult,
        ),
      ),
    ).then((_) => onClose?.call());
  }

  /// The ProviderScope overrides that mount a flow with [effectiveConfig] and,
  /// when a workflow was resolved before mount, its preloaded server config.
  /// The list itself lives in kyc_flow_scope.dart, which both hosts import.
  static List<Override> _overridesFor(
    MyazaKYCConfig effectiveConfig,
    ServerSdkConfig? preloaded,
  ) =>
      kycFlowOverrides(effectiveConfig, preloaded);
}

/// Embeddable widget version. Wrap in your own layout.
class MyazaKYCWidget extends StatelessWidget {
  final MyazaKYCConfig config;
  final void Function(KYCSubmission)? onSubmit;
  final void Function(KYCError)? onError;
  final VoidCallback? onClose;
  final void Function(KYCResult)? onResult;

  const MyazaKYCWidget({
    super.key,
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  Widget build(BuildContext context) {
    // Fail loud on an invalid key prefix (throws ArgumentError).
    detectEnvironment(config.apiKey);

    // Workflow-driven: resolve first, then mount with the merged config.
    if (config.workflowId != null && config.workflowId!.trim().isNotEmpty) {
      return _EmbeddedWorkflowGate(
        config: config,
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
        onResult: onResult,
      );
    }

    return ProviderScope(
      overrides: MyazaKYC._overridesFor(config, null),
      child: _KycFlowWidget(
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
        onResult: onResult,
      ),
    );
  }
}

// ─── Embedded workflow gate ───────────────────────────────────────────────────
//
// The embeddable widget's resolve-before-mount: while the workflow resolves it
// shows a loader; on success it mounts the flow with the merged config +
// preloaded server config; on failure it reports onError once and shows the
// error message inline (there's no modal to pop, unlike MyazaKYC.show).

class _EmbeddedWorkflowGate extends StatefulWidget {
  final MyazaKYCConfig config;
  final void Function(KYCSubmission)? onSubmit;
  final void Function(KYCError)? onError;
  final VoidCallback? onClose;
  final void Function(KYCResult)? onResult;

  const _EmbeddedWorkflowGate({
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  State<_EmbeddedWorkflowGate> createState() => _EmbeddedWorkflowGateState();
}

class _EmbeddedWorkflowGateState extends State<_EmbeddedWorkflowGate> {
  late final Future<WorkflowGateResult> _future;
  bool _errorReported = false;

  @override
  void initState() {
    super.initState();
    _future = resolveWorkflowResult(widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkflowGateResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(MyazaSpacing.xl),
              child: MyazaPulseLoader(),
            ),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          final kycErr = err is KYCError
              ? err
              : const KYCError(
                  code: 'invalid_workflow',
                  message: 'This verification workflow could not be loaded.',
                );
          if (!_errorReported) {
            _errorReported = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.onError?.call(kycErr),
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(MyazaSpacing.xl),
              child: Text(kycErr.message, textAlign: TextAlign.center),
            ),
          );
        }
        final result = snap.data!;
        return ProviderScope(
          overrides: MyazaKYC._overridesFor(result.config, result.serverConfig),
          child: _KycFlowWidget(
            onSubmit: widget.onSubmit,
            onError: widget.onError,
            onClose: widget.onClose,
            onResult: widget.onResult,
          ),
        );
      },
    );
  }
}

// ─── Internal flow widget ─────────────────────────────────────────────────────

class _KycFlowWidget extends ConsumerStatefulWidget {
  final bool isFullScreen;
  final void Function(KYCSubmission)? onSubmit;
  final void Function(KYCError)? onError;
  final VoidCallback? onClose;
  final void Function(KYCResult)? onResult;

  const _KycFlowWidget({
    this.isFullScreen = false,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  ConsumerState<_KycFlowWidget> createState() => _KycFlowWidgetState();
}

class _KycFlowWidgetState extends ConsumerState<_KycFlowWidget>
    with PortraitLock {
  /// One stable key per step, so a step's State survives being REPARENTED.
  ///
  /// The full-bleed camera swaps the whole shell — sheet-with-chrome for a bare
  /// Scaffold — which puts the step screen at a different position in the tree.
  /// Without a GlobalKey, Flutter tears the old State down and builds a fresh
  /// one: the document step lost `_ready`, fell back to its primer, lowered the
  /// immersive flag, and the shell swapped straight back — a remount loop where
  /// the camera never opened at all.
  final _stepKeys = <KYCStep, GlobalKey>{};

  // Ensures a fatal config-load failure is reported to onError at most once.
  bool _configErrorReported = false;

  @override
  void initState() {
    // PortraitLock pins the flow upright for its lifetime and restores the
    // host's orientations on close — see utils/portrait_lock.dart for why the
    // camera preview makes this load-bearing rather than cosmetic.
    super.initState();

    // On Android both on-device models are fetched by Play Services rather than
    // shipped in the app. Asking now lets the downloads overlap the first
    // screens, so the liveness step and the passport scanner rarely have to
    // wait. The text model is the larger one and is needed earlier. A no-op
    // off Android and once a model is on the phone.
    primeFaceModel();
    primeTextModel();
  }

  @override
  void dispose() {
    // The orientation release is PortraitLock's.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final config = ref.read(kycConfigProvider);

    final step = state.currentStep;
    var meta = _kStepMeta[step]!;

    // The entrance step framing street imagery describes THAT, not a camera.
    if (step == KYCStep.addressEntrance &&
        ref.watch(
            kYCNotifierProvider.select((s) => s.addressEntranceFraming))) {
      meta = const _StepMeta(
        'Show the entrance',
        'Frame your entrance in the street imagery. No camera needed.',
      );
    }

    // The ID input step names the ID it wants. The step asks for the number and
    // nothing else: the applicant's name comes from the integrator, through the
    // config or the session, never typed here.
    if (step == KYCStep.idInput && state.selectedIdType != null) {
      meta = _StepMeta(
        'Enter your ${state.selectedIdType!.label}',
        meta.description,
      );
    }

    // Supporting documents: the line follows the COUNTS, so it says how many
    // have to be produced rather than how to read an asterisk. Resolved the
    // same way the screen resolves its slots, or the header could name a
    // number the body does not show.
    if (step == KYCStep.supportingDocuments) {
      meta = _StepMeta(
        meta.title,
        supportingDocumentsIntro(
          resolveSupportingDocuments(
            config.supportingDocuments,
            verifiedIdComposites(config, state),
          ),
        ),
      );
    }

    // A KYB flow's pin is the BUSINESS PREMISES, so the step introduces itself
    // as that rather than as the applicant's home address.
    if (config.subjectType == 'business') {
      if (step == KYCStep.addressCollection) {
        meta = _StepMeta('Is the pin on the premises?', meta.description);
      } else if (step == KYCStep.addressReview) {
        meta = _StepMeta('Confirm the premises', meta.description);
      }
    }

    // The presence primer carries its own heading, so the step's title would
    // sit above it saying something else. Blanked the way the consent step's
    // is, which is the same situation: a screen that introduces itself.
    if (kAddressFlowOrder.contains(step) &&
        addressIntroGateShowing(config, state, step)) {
      meta = const _StepMeta('');
    }

    // Proof of address states its own recency window, so the description has to
    // carry the workflow's maxAgeDays rather than say "recent".
    if (step == KYCStep.proofOfAddress) {
      final poa = config.proofOfAddress;
      final days = poa?.maxAgeDays ?? 90;
      // Ask for what the server will check: where the workflow's name rule is
      // off for the picked kind in this country (a Nigerian utility bill names
      // the meter, not the tenant), asking for "your name" sends people hunting
      // for a document they do not have. Mirrors the web and RN headers.
      final kind = state.poaDocumentType == null
          ? null
          : PoaDocumentType.tryFromKey(state.poaDocumentType!);
      final nameNeeded = poa == null ||
          poa.namePolicyFor(state.selectedCountry ?? config.country, kind) !=
              PoaNameRule.off;
      meta = _StepMeta(
        meta.title,
        'Upload a document that shows your '
        '${nameNeeded ? 'name and home address' : 'home address'}, issued '
        'within the last $days days.',
      );
    }

    // The contact steps turn their description from a promise ("we'll send a
    // code…") into an instruction ("enter the code we sent to…") once a code is
    // out, and name the delivery channel the user picked — matching the web
    // SDK. The screen publishes that via contactChannel/Via/Destination,
    // because the header lives out here and cannot see its state.
    if (step == KYCStep.contactEmail || step == KYCStep.contactPhone) {
      final isPhone = step == KYCStep.contactPhone;
      // Only trust state raised by THIS step: both contact steps are the same
      // screen, so a leftover email entry must never caption the phone step.
      final live = state.contactChannel == (isPhone ? 'phone' : 'email');
      final by = isPhone && live && state.contactVia.isNotEmpty
          ? ' by ${kChannelLabels[state.contactVia] ?? state.contactVia}'
          : '';

      if (live && state.contactDestination.isNotEmpty) {
        final length = (isPhone
                ? config.phoneVerification?.codeLength
                : config.emailVerification?.codeLength) ??
            6;
        meta = _StepMeta(
          meta.title,
          'Enter the $length-digit code we sent to '
          '${state.contactDestination}$by.',
        );
      } else if (isPhone) {
        meta = _StepMeta(
          meta.title,
          "We'll send a one-time code$by to confirm this number belongs to you.",
        );
      }
    }

    // For document capture, swap title/description based on the review phase
    // communicated by DocumentCaptureScreen via docReviewPhase.
    if (step == KYCStep.documentCapture) {
      final docPhase = ref.watch(
        kYCNotifierProvider.select((s) => s.docReviewPhase),
      );
      final idTypeLabel = state.selectedIdType?.label ?? 'Document';
      // Camera off on this workflow: every side is a picked photo, so the
      // header must not talk about framing or scanning.
      final uploadOnly = documentCaptureMethodsFor(config).uploadOnly;
      meta = uploadOnly
          ? switch (docPhase) {
              'front_preview' => const _StepMeta(
                  'Front Side Added',
                  'Looks good? Tap Next to add a photo of the back.',
                ),
              'camera_back' => _StepMeta(
                  'Upload Back Side',
                  'Now choose a clear photo of the back of your $idTypeLabel.',
                ),
              'review' => _StepMeta(
                  'Review Your $idTypeLabel',
                  'Tap Continue to upload and submit your document.',
                ),
              _ => _StepMeta(
                  'Upload Your $idTypeLabel',
                  'Choose a clear photo of your $idTypeLabel from your device.',
                ),
            }
          : switch (docPhase) {
        'front_preview' => const _StepMeta(
            'Front Side Captured',
            'Looks good? Tap Next to flip the card and scan the back side.',
          ),
        'camera_back' => _StepMeta(
            'Scan Back Side',
            'Now place the BACK of your $idTypeLabel within the frame.',
          ),
        'review' => _StepMeta(
            'Review Your $idTypeLabel',
            'Tap Continue to upload and submit your document.',
          ),
        _ => _StepMeta(
            'Capture Your $idTypeLabel',
            'Photograph your $idTypeLabel — position it within the frame and hold steady.',
          ),
      };
    }

    // For the liveness step in selfie-review phase, swap to the review title.
    if (step == KYCStep.liveness) {
      final livenessPhase = ref.watch(
        livenessNotifierProvider.select((s) => s.phase),
      );
      if (livenessPhase == LivenessPhase.complete) {
        meta = const _StepMeta(
          'Selfie Captured',
          'Review your selfie before continuing.',
        );
      }
    }

    // ── Resolve theme ──────────────────────────────────────────────────────
    final themeMode = ref.watch(kycThemeModeProvider);
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && systemBrightness == Brightness.dark);
    final baseScheme = isDark ? MyazaColorScheme.dark : MyazaColorScheme.light;
    // Fold in the dark overrides FIRST: the appearance is applied on top of the
    // active base scheme, so a light background would otherwise overwrite the
    // dark one and the toggle would do nothing on a branded flow.
    final colorScheme =
        applyAppearance(baseScheme, config.appearance?.forBrightness(isDark));

    // ── Resolve org branding for the persistent header ─────────────────────
    // `appearance.logo = 'default'` pulls the org logo from the server config
    // response; any other value is a literal network URL. Falls back to the
    // local logoAsset, then to nothing.
    final appearance = config.appearance;
    final branding = state.serverConfig.branding;
    final appearanceLogo = appearance?.logo;
    // The server's `branding.logo` is absolute, built from its PUBLIC_SERVER_URL
    // — which can differ from the host the SDK reaches it on (a dev tunnel, a
    // LAN IP vs `.local`, …), so it may 404 on-device. Rebase it onto the URL
    // the SDK actually talks to; a consumer's literal `appearance.logo` URL is
    // used as-is.
    final logoUrl = appearanceLogo == 'default'
        ? rebaseServerUrl(
            branding?.logo,
            resolveBaseUrl(config.apiKey, devUrl: config.devUrl),
          )
        : appearanceLogo;
    final companyName = appearance?.companyName ?? branding?.companyName;

    void onToggleTheme() {
      final current = ref.read(kycThemeModeProvider);
      final effective = current == ThemeMode.system
          ? (systemBrightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light)
          : current;
      ref.read(kycThemeModeProvider.notifier).state =
          effective == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    }

    // ── Compute step info (progress fraction + total count) ───────────────
    final stepInfo = _computeStepInfo(state, config);
    final progress = stepInfo?.progress;

    // ── Back callback (null = hide back button) ────────────────────────────
    // Hidden on the flow's OPENING step (consent, or the first real step when
    // the workflow switched the consent screen off), not on consent by name.
    // A multi-ID run returns to the ID picker for its next check, where Back
    // means "redo the previous one", so a committed slot keeps the arrow.
    final opening = openingStep(config, serverConfig: state.serverConfig);
    final VoidCallback? onBack = switch (step) {
      KYCStep.submitted => null, // terminal
      _ when step == opening && state.multiIdSlots.isEmpty => null,
      _ => notifier.previousStep,
    };

    // ── Prevent dismissal during submission, or when the consumer disables
    //    close (programmatic pop is then the only way out). ──────────────────
    final canDismiss = step != KYCStep.submitted && !config.disableClose;

    // ── Fatal config-load failure (e.g. wrong API key) blocks the flow ─────
    // It replaces the normal step with a clear error screen, strips the
    // progress bar / back button, and reports the error to onError once.
    final serverConfig = state.serverConfig;
    final configError =
        serverConfig.status == ServerConfigStatus.error && serverConfig.fatal
            ? (serverConfig.error ??
                'Unable to start verification. Please try again.')
            : null;
    if (configError != null && !_configErrorReported) {
      _configErrorReported = true;
      final kycError = KYCError(
        code: switch (serverConfig.statusCode) {
          401 => 'invalid_api_key',
          403 => 'feature_disabled',
          _ => 'unknown',
        },
        message: configError,
      );
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onError?.call(kycError));
    }

    // ── Screen routing ────────────────────────────────────────────────────
    final screen = configError != null
        ? _ConfigErrorScreen(
            message: configError,
            onClose: () {
              widget.onClose?.call();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          )
        : _screenWithMultiId(step);

    // Keyed so the SAME State moves between the two shells instead of being
    // rebuilt — see _stepKeys.
    final keyedScreen = configError != null
        ? screen
        : KeyedSubtree(
            key: _stepKeys.putIfAbsent(step, GlobalKey.new),
            child: screen,
          );

    // Show the country flag beside the title on the ID-selection steps (the
    // effective country — the picked one in a multi-region flow).
    final headerCountry = configError == null &&
            (step == KYCStep.idType || step == KYCStep.idInput)
        ? effectiveCountry(config, state)
        : null;

    final sheet = KycBottomSheet(
      environment: state.serverConfig.environment,
      title: configError != null ? '' : meta.title,
      description: configError != null ? null : meta.description,
      progress: configError != null ? null : progress,
      stepCount: configError != null ? null : stepInfo?.stepCount,
      onBack: configError != null ? null : onBack,
      onClose: widget.onClose,
      canDismiss: canDismiss,
      isFullScreen: widget.isFullScreen,
      isDark: isDark,
      // Only wire the toggle when the consumer opted in; a null callback hides
      // the button and keeps the flow on the appearance theme.
      onToggleTheme: config.showThemeToggle ? onToggleTheme : null,
      progressStyle: config.progressStyle,
      // Hide the brand bar on a fatal config error — show a clean, chrome-free
      // error screen (just the theme/fullscreen controls), like the web SDK.
      logoUrl: configError != null ? null : logoUrl,
      logoAsset: configError != null ? null : appearance?.logoAsset,
      companyName: configError != null ? null : companyName,
      country: headerCountry,
      // Which steps get the whole body instead of the shared scroll view: see
      // _fillsViewport.
      fillsViewport: configError == null && _fillsViewport(step),
      child: keyedScreen,
    );

    // ── Immersive capture ─────────────────────────────────────────────────
    // A camera step asks for the whole screen (state.immersiveCapture). The
    // sheet's header, padding and scroll view are what force a small viewfinder
    // on a short phone — and a camera you have to SCROLL to is a broken camera.
    // So the sheet is bypassed entirely: the screen owns the display, edge to
    // edge and behind the system bars, and draws its own back/close controls.
    // Scoped to the document step as well as the flag: if that step unmounts
    // while the flag is still raised, the NEXT step must not inherit a
    // chrome-free shell.
    final immersive = configError == null &&
        state.immersiveCapture &&
        step == KYCStep.documentCapture;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      // Bottom system-nav / gesture area uses the body background (not the
      // tinted header that the Scaffold paints behind the status bar).
      systemNavigationBarColor: colorScheme.background,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    Widget themed(Widget child) => Theme(
          data: Theme.of(context).copyWith(extensions: [colorScheme]),
          child: child,
        );

    if (immersive) {
      return themed(AnnotatedRegion<SystemUiOverlayStyle>(
        // Light icons: the camera feed behind the status bar is dark.
        value: overlayStyle.copyWith(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          // No SafeArea: the feed runs under the bars on purpose. The screen
          // insets its own controls.
          body: keyedScreen,
        ),
      ));
    }

    if (widget.isFullScreen) {
      return themed(AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          // Body background fills the bottom system-nav/gesture inset, keeping
          // it the dark body colour. The status-bar inset is painted with the
          // header tint below so the top matches the header band.
          backgroundColor: colorScheme.background,
          body: Column(
            children: [
              // Strip behind the status bar. Normally the header tint so the
              // top matches the header band — but when the environment banner
              // is showing, the banner is what sits directly below, so the
              // strip takes ITS amber instead and the warning reads as one
              // unbroken band from the top of the screen (matching RN). Both
              // are translucent over the same Scaffold background, so the
              // composite is identical to the banner's own.
              Container(
                height: MediaQuery.of(context).padding.top,
                color: SandboxBanner.showsFor(state.serverConfig.environment)
                    ? SandboxBanner.tint
                    : kycHeaderSurface(colorScheme, isDark: isDark),
              ),
              Expanded(child: SafeArea(top: false, child: sheet)),
            ],
          ),
        ),
      ));
    }

    return themed(AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: LayoutBuilder(
        builder: (ctx, _) {
          final sheetHeight = MediaQuery.of(context).size.height * 0.92;
          return SizedBox(height: sheetHeight, child: sheet);
        },
      ),
    ));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Progress indicator, computed from the same `buildStepOrder` the navigation
  /// uses (single source of truth). The terminal `submitted` step is excluded
  /// from the count.
  ({double progress, int stepCount})? _computeStepInfo(
      KYCState state, MyazaKYCConfig config) {
    final step = state.currentStep;
    if (step == KYCStep.submitted) return null;

    final steps = buildStepOrder(config, state)
        .where((s) => s != KYCStep.submitted)
        .toList();
    final idx = steps.indexOf(step);
    if (idx < 0) return null;
    return (progress: (idx + 1) / steps.length, stepCount: steps.length);
  }

  /// The steps given the sheet's whole body instead of its shared scroll view.
  ///
  /// Country select owns its own scroll (pinned search + full-height list),
  /// matching the web SDK's flex-1 body. Document capture wants the full
  /// viewport too: it is about to go immersive, and on the frames before that
  /// flag flips it would otherwise render inside the scroll view with unbounded
  /// height, which the camera cannot lay out against. The address pin and
  /// entrance steps fill it as well: the map owns every touch, so Continue rides
  /// StickyActions at the bottom of a BOUNDED body rather than under a surface a
  /// short phone cannot scroll past.
  ///
  /// Every other step lays out inside the scroll view, so its height is
  /// unbounded and nothing wrapping its screen may flex it.
  static bool _fillsViewport(KYCStep step) =>
      step == KYCStep.countrySelect ||
      step == KYCStep.documentCapture ||
      step == KYCStep.addressCollection ||
      step == KYCStep.addressEntrance;

  /// The steps a multi-ID run walks once PER ID — the ones whose screen is
  /// about one particular check and therefore need the position strip above.
  static const Set<KYCStep> _multiIdSteps = {
    KYCStep.idType,
    KYCStep.idInput,
    KYCStep.documentCapture,
    KYCStep.nfc,
    KYCStep.liveness,
  };

  /// Wraps a step's screen with the multi-ID position strip when a run is
  /// active, so a three-ID run is not three visits to the same-looking screen
  /// with nothing saying which is which.
  Widget _screenWithMultiId(KYCStep step) {
    final plan = ref.read(kYCNotifierProvider.notifier).multiIdPlan();
    if (plan == null || !_multiIdSteps.contains(step)) return _screenForStep(step);
    // A step inside the sheet's scroll view has UNBOUNDED height, and an
    // Expanded cannot lay out there: a debug build asserts and paints nothing,
    // which left the multi-ID ID picker blank (2026-09-15; a release build skips
    // the assertion and happened to render). Only a step given the whole body
    // (document capture, whose immersive shell is bounded too) may flex its
    // screen under the strip.
    if (!_fillsViewport(step)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [MultiIdProgress(plan: plan), _screenForStep(step)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MultiIdProgress(plan: plan),
        Expanded(child: _screenForStep(step)),
      ],
    );
  }

  Widget _screenForStep(KYCStep step) => switch (step) {
        KYCStep.consent => const ConsentScreen(),
        KYCStep.countrySelect => const CountrySelectScreen(),
        KYCStep.idType => const IdTypeScreen(),
        KYCStep.documentCapture =>
          DocumentCaptureScreen(onError: widget.onError),
        KYCStep.idInput => const IdInputScreen(),
        KYCStep.liveness => LivenessScreen(onError: widget.onError),
        KYCStep.submitted => SubmittedScreen(
            onSubmitted: widget.onSubmit,
            onError: widget.onError,
            onResult: widget.onResult,
            onDone: () {
              widget.onClose?.call();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        // Steps below are gated OFF in buildStepOrder until their workstreams
        // land (country-select WS3, questionnaire WS4, contact WS4.5, PoA WS5,
        // NFC Phase 2), so they're never routed to yet. Placeholder keeps the
        // switch exhaustive; each WS replaces its case with the real screen.
        KYCStep.questionnaire => const QuestionnaireScreen(),
        KYCStep.businessDetails => const BusinessDetailsScreen(),
        KYCStep.businessKeyPeople => const BusinessKeyPeopleScreen(),
        KYCStep.applicantRole => const ApplicantRoleScreen(),
        KYCStep.businessDocuments => BusinessDocumentsScreen(
            onError: (e) => widget.onError?.call(
              e is KYCError
                  ? e
                  : const KYCError(
                      code: 'upload_failed',
                      message: 'Business document upload failed.'),
            ),
          ),
        KYCStep.supportingDocuments => SupportingDocumentsScreen(
            onError: (e) => widget.onError?.call(
              e is KYCError
                  ? e
                  : const KYCError(
                      code: 'upload_failed',
                      message: 'Supporting document upload failed.'),
            ),
          ),
        KYCStep.proofOfAddress => ProofOfAddressScreen(
            onError: (e) => widget.onError?.call(
                  e is KYCError
                      ? e
                      : const KYCError(
                          code: 'upload_failed',
                          message: 'Proof of address upload failed.'),
                )),
        // The address flow: find it, confirm it, show it, commit it. Each is a
        // real step in the order (see step_order.dart), so the progress bar
        // and the header's back arrow need nothing special here.
        KYCStep.addressSearch => const AddressSearchStep(),
        KYCStep.addressCollection => const AddressPinStep(),
        KYCStep.addressEntrance => const AddressEntranceStep(),
        KYCStep.addressReview => const AddressReviewStep(),
        // Both contact steps mount the SAME widget type, so without distinct
        // keys Flutter matches them by (runtimeType, key) and REUSES the State
        // across email → phone: the phone step would inherit the email step's
        // in-flight flags (stuck spinner), challenge id and destination.
        KYCStep.contactEmail => const ContactVerificationScreen(
            key: ValueKey('contact-email'), channel: 'email'),
        KYCStep.contactPhone => const ContactVerificationScreen(
            key: ValueKey('contact-phone'), channel: 'phone'),
        KYCStep.nfc => const NfcScreen(),
      };
}

// ─── Config error screen ──────────────────────────────────────────────────────
//
// Shown when the SDK can't load its server config because of a fatal auth
// failure (e.g. a wrong API key). Blocks the flow so the user gets a clear
// message instead of a silently broken ID-type list. Mirrors the web SDK's
// ConfigErrorScreen and the styling of SubmittedScreen's error view.

class _ConfigErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _ConfigErrorScreen({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    // Mirrors the web SDK's ConfigErrorScreen: icon → title → message →
    // full-width Close button stacked as one vertically-centered group
    // (gap-6 / 24px between blocks, 4px within the text block), with a single
    // fade-in on the whole group.
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
            // Icon circle (80×80, destructive @10%), centered.
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: MyazaColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const MyazaIcon(
                  MyazaIcons.circleAlert,
                  size: 40,
                  color: MyazaColors.error,
                ),
              ),
            ),
            const SizedBox(height: MyazaSpacing.lg),
            Text(
              'Unable to start verification',
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
            MyazaButton(label: 'Close', onPressed: onClose),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}
