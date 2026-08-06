import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemUiOverlayStyle, SystemChrome, DeviceOrientation;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../liveness/liveness_types.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/step_order.dart';
import '../providers/theme_provider.dart';
import '../screens/business_details_screen.dart';
import '../screens/consent_screen.dart';
import '../screens/contact_verification_screen.dart';
import '../screens/country_select_screen.dart';
import '../screens/document_capture_screen.dart';
import '../screens/id_input_screen.dart';
import '../screens/id_type_screen.dart';
import '../screens/nfc_screen.dart';
import '../screens/proof_of_address_screen.dart';
import '../screens/questionnaire_screen.dart';
import 'myaza_pulse_loader.dart';
import 'workflow_gate.dart';
import '../screens/liveness_screen.dart';
import '../screens/submitted_screen.dart';
import '../utils/resolve_url.dart';
import 'kyc_bottom_sheet.dart';
import 'myaza_button.dart';

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
  // idInput description is computed dynamically from selectedIdType.
  KYCStep.idInput: _StepMeta('Enter Your Details'),
  KYCStep.liveness: _StepMeta(
    'Face Verification',
    'Follow the on-screen instructions',
  ),
  // Optional steps (populated with real copy by their workstreams). Present
  // here so the `_kStepMeta[step]!` lookup never misses once a step is enabled.
  KYCStep.contactEmail: _StepMeta(
    'Verify Your Email',
    'Confirm your email address with a one-time code.',
  ),
  KYCStep.contactPhone: _StepMeta(
    'Verify Your Phone',
    'Confirm your phone number with a one-time code.',
  ),
  KYCStep.countrySelect: _StepMeta(
    'Where was your ID issued?',
    'Choose the country that issued your identity document.',
  ),
  KYCStep.nfc: _StepMeta(
    'Scan Document Chip',
    'Hold your document to the back of your phone.',
  ),
  KYCStep.proofOfAddress: _StepMeta(
    'Proof of Address',
    'Upload a recent document showing your address.',
  ),
  KYCStep.questionnaire: _StepMeta(
    'A Few More Questions',
    'Please answer the following to complete your verification.',
  ),
  KYCStep.businessDetails: _StepMeta(
    'Business Details',
    'Tell us about the business you’re verifying.',
  ),
  // submitted has no title — the screen owns its layout.
  KYCStep.submitted: _StepMeta(''),
};

// ─── Appearance → color scheme ────────────────────────────────────────────────
//
// Maps the consumer's MyazaKYCAppearance overrides onto the base (light/dark)
// MyazaColorScheme. Unset colors keep the built-in token. When a primaryColor
// is given, the primary tint family (50/100/200) is derived from it so the whole
// brand family follows; an explicit accentColor overrides the 100 tint.

MyazaColorScheme _applyAppearance(
  MyazaColorScheme base,
  MyazaKYCAppearance? a,
) {
  if (a == null) return base;
  final primary = a.primaryColor ?? base.primary;
  final background = a.backgroundColor ?? base.background;
  final hasPrimary = a.primaryColor != null;
  Color tint(double opacity) =>
      Color.alphaBlend(primary.withValues(alpha: opacity), background);

  return base.copyWith(
    primary: primary,
    onPrimary: a.primaryTextColor,
    background: background,
    backgroundSecondary: a.surfaceColor,
    border: a.borderColor,
    textDark: a.textColor,
    primary50: hasPrimary ? tint(0.06) : null,
    primary100: a.accentColor ?? (hasPrimary ? tint(0.12) : null),
    primary200: hasPrimary ? tint(0.24) : null,
  );
}

/// Maps the appearance's initial theme to a ThemeMode. Null appearance/theme
/// follows the device setting.
ThemeMode _initialThemeMode(MyazaKYCAppearance? a) => switch (a?.theme) {
      MyazaThemeMode.light => ThemeMode.light,
      MyazaThemeMode.dark => ThemeMode.dark,
      null => ThemeMode.system,
    };

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
        ),
      ),
    ).then((_) => onClose?.call());
  }

  /// The ProviderScope overrides that mount a flow with [effectiveConfig] and,
  /// when a workflow was resolved before mount, its preloaded server config.
  static List<Override> _overridesFor(
    MyazaKYCConfig effectiveConfig,
    ServerSdkConfig? preloaded,
  ) =>
      [
        // Config must be first — the notifiers read it during build.
        kycConfigProvider.overrideWithValue(effectiveConfig),
        if (preloaded != null)
          preloadedServerConfigProvider.overrideWithValue(preloaded),
        // Scope all three KYC notifiers to this container so they read
        // kycConfigProvider from the override above, not from the root
        // ProviderScope (which has no override and would throw).
        kYCNotifierProvider.overrideWith(KYCNotifier.new),
        cameraNotifierProvider.overrideWith(CameraNotifier.new),
        livenessNotifierProvider.overrideWith(LivenessNotifier.new),
        kycThemeModeProvider
            .overrideWith((ref) => _initialThemeMode(effectiveConfig.appearance)),
      ];
}

/// Embeddable widget version. Wrap in your own layout.
class MyazaKYCWidget extends StatelessWidget {
  final MyazaKYCConfig config;
  final void Function(KYCSubmission)? onSubmit;
  final void Function(KYCError)? onError;
  final VoidCallback? onClose;

  const MyazaKYCWidget({
    super.key,
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
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
      );
    }

    return ProviderScope(
      overrides: MyazaKYC._overridesFor(config, null),
      child: _KycFlowWidget(
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
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

  const _EmbeddedWorkflowGate({
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
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

  const _KycFlowWidget({
    this.isFullScreen = false,
    this.onSubmit,
    this.onError,
    this.onClose,
  });

  @override
  ConsumerState<_KycFlowWidget> createState() => _KycFlowWidgetState();
}

class _KycFlowWidgetState extends ConsumerState<_KycFlowWidget> {
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
    super.initState();
    // The KYC flow is a portrait-only UI, and on Android the camera preview
    // (CameraX) rotates to follow the DISPLAY orientation — so if the host app
    // permits rotation, tilting the phone to photograph a document (holding it
    // flat over the page) flips the feed sideways after a moment. Pin the flow
    // to portrait for its lifetime so the display — and thus the preview — stays
    // upright. The host's orientations are restored on close.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    // Release the lock. Flutter doesn't expose the host's PREVIOUS preferred
    // orientations, so restore the default (all) rather than guess — a host that
    // wants a specific lock re-applies it after the flow returns.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final config = ref.read(kycConfigProvider);

    final step = state.currentStep;
    var meta = _kStepMeta[step]!;

    // For the ID input step, build a dynamic description from the selected type.
    if (step == KYCStep.idInput && state.selectedIdType != null) {
      meta = _StepMeta(
        meta.title,
        'Provide your ${state.selectedIdType!.label} for verification.',
      );
    }

    // For document capture, swap title/description based on the review phase
    // communicated by DocumentCaptureScreen via docReviewPhase.
    if (step == KYCStep.documentCapture) {
      final docPhase = ref.watch(
        kYCNotifierProvider.select((s) => s.docReviewPhase),
      );
      final idTypeLabel = state.selectedIdType?.label ?? 'Document';
      meta = switch (docPhase) {
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
        (themeMode == ThemeMode.system &&
            systemBrightness == Brightness.dark);
    final baseScheme = isDark ? MyazaColorScheme.dark : MyazaColorScheme.light;
    final colorScheme = _applyAppearance(baseScheme, config.appearance);

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
    final VoidCallback? onBack = switch (step) {
      KYCStep.consent   => null, // first step
      KYCStep.submitted => null, // terminal
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
        : _screenForStep(step);

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
      // Hide the brand bar on a fatal config error — show a clean, chrome-free
      // error screen (just the theme/fullscreen controls), like the web SDK.
      logoUrl: configError != null ? null : logoUrl,
      logoAsset: configError != null ? null : appearance?.logoAsset,
      companyName: configError != null ? null : companyName,
      country: headerCountry,
      // Country select owns its own scroll (pinned search + full-height list),
      // matching the web SDK's flex-1 body. Every other step keeps the shared
      // scroll view.
      // Country select owns its own scrolling list. Document capture wants the
      // full viewport too: it is about to go immersive, and on the frames
      // before that flag flips it would otherwise render inside the sheet's
      // scroll view with unbounded height — which the camera cannot lay out
      // against.
      fillsViewport: configError == null &&
          (step == KYCStep.countrySelect || step == KYCStep.documentCapture),
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
              // Tinted strip behind the status bar → matches the header band.
              Container(
                height: MediaQuery.of(context).padding.top,
                color: kycHeaderSurface(colorScheme, isDark: isDark),
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

  Widget _screenForStep(KYCStep step) => switch (step) {
        KYCStep.consent         => const ConsentScreen(),
        KYCStep.countrySelect   => const CountrySelectScreen(),
        KYCStep.idType          => const IdTypeScreen(),
        KYCStep.documentCapture => DocumentCaptureScreen(onError: widget.onError),
        KYCStep.idInput         => const IdInputScreen(),
        KYCStep.liveness        => LivenessScreen(onError: widget.onError),
        KYCStep.submitted       => SubmittedScreen(
            onSubmitted: widget.onSubmit,
            onError: widget.onError,
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
        KYCStep.questionnaire   => const QuestionnaireScreen(),
        KYCStep.businessDetails => const BusinessDetailsScreen(),
        KYCStep.proofOfAddress  =>
          ProofOfAddressScreen(onError: (e) => widget.onError?.call(
                e is KYCError
                    ? e
                    : const KYCError(
                        code: 'upload_failed',
                        message: 'Proof of address upload failed.'),
              )),
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
                child: const Icon(
                  Icons.error_outline_rounded,
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
