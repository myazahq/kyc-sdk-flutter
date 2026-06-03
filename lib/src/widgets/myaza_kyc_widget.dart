import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../config/id_types.dart';
import '../liveness/liveness_types.dart';
import '../providers/camera_provider.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/consent_screen.dart';
import '../screens/document_capture_screen.dart';
import '../screens/id_input_screen.dart';
import '../screens/id_type_screen.dart';
import '../screens/liveness_screen.dart';
import '../screens/submitted_screen.dart';
import 'kyc_bottom_sheet.dart';

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
/// ```dart
/// MyazaKYC.show(
///   context: context,
///   config: MyazaKYCConfig(apiKey: '...', country: Country.NG, environment: KYCEnvironment.production),
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
  }) {
    final overrides = [
      // Config must be first — the notifiers read it during build.
      kycConfigProvider.overrideWithValue(config),
      // Scope all three KYC notifiers to this container so they read
      // kycConfigProvider from the override above, not from the root
      // ProviderScope (which has no override and would throw).
      kYCNotifierProvider.overrideWith(KYCNotifier.new),
      cameraNotifierProvider.overrideWith(CameraNotifier.new),
      livenessNotifierProvider.overrideWith(LivenessNotifier.new),
      kycThemeModeProvider
          .overrideWith((ref) => _initialThemeMode(config.appearance)),
    ];

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

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
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
    return ProviderScope(
      overrides: [
        kycConfigProvider.overrideWithValue(config),
        kYCNotifierProvider.overrideWith(KYCNotifier.new),
        cameraNotifierProvider.overrideWith(CameraNotifier.new),
        livenessNotifierProvider.overrideWith(LivenessNotifier.new),
        kycThemeModeProvider
            .overrideWith((ref) => _initialThemeMode(config.appearance)),
      ],
      child: _KycFlowWidget(
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
      ),
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
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final config = ref.read(kycConfigProvider);

    final step = state.currentStep;
    var meta = _kStepMeta[step]!;

    // For the ID input step, build a dynamic description from the selected type.
    if (step == KYCStep.idInput && state.selectedIdType != null) {
      final idCfg = getIdTypeConfig(config.country, state.selectedIdType!);
      if (idCfg != null) {
        meta = _StepMeta(
          meta.title,
          'Provide your ${idCfg.label} for verification.',
        );
      }
    }

    // For document capture, swap title/description based on the review phase
    // communicated by DocumentCaptureScreen via docReviewPhase.
    if (step == KYCStep.documentCapture) {
      final docPhase = ref.watch(
        kYCNotifierProvider.select((s) => s.docReviewPhase),
      );
      final idTypeLabel = state.selectedIdType != null
          ? getIdTypeConfig(config.country, state.selectedIdType!)?.label ??
              'Document'
          : 'Document';
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
    final logoUrl =
        appearanceLogo == 'default' ? branding?.logo : appearanceLogo;
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

    // ── Prevent dismissal during submission ───────────────────────────────
    final canDismiss = step != KYCStep.submitted;

    // ── Screen routing ────────────────────────────────────────────────────
    final screen = _screenForStep(step);

    // Show the country flag beside the title on the ID-selection steps.
    final headerCountry =
        (step == KYCStep.idType || step == KYCStep.idInput) ? config.country : null;

    final sheet = KycBottomSheet(
      title: meta.title,
      description: meta.description,
      progress: progress,
      stepCount: stepInfo?.stepCount,
      onBack: onBack,
      onClose: widget.onClose,
      canDismiss: canDismiss,
      isFullScreen: widget.isFullScreen,
      isDark: isDark,
      onToggleTheme: onToggleTheme,
      logoUrl: logoUrl,
      logoAsset: appearance?.logoAsset,
      companyName: companyName,
      country: headerCountry,
      child: screen,
    );

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

  /// 5-step progress indicator: consent, idType, (documentCapture | idInput),
  /// liveness, submitted. Liveness is conditionally included.
  ({double progress, int stepCount})? _computeStepInfo(
      KYCState state, MyazaKYCConfig config) {
    final step = state.currentStep;
    if (step == KYCStep.submitted) return null;

    final hasCapture = config.enableDocumentCapture &&
        _selectedRequiresCapture(state, config);
    final hasLiveness = config.enableLiveness && config.enableSelfie;

    final steps = [
      KYCStep.consent,
      KYCStep.idType,
      if (hasCapture) KYCStep.documentCapture else KYCStep.idInput,
      if (hasLiveness) KYCStep.liveness,
    ];

    final idx = steps.indexOf(step);
    if (idx < 0) return null;
    return (progress: (idx + 1) / steps.length, stepCount: steps.length);
  }

  bool _selectedRequiresCapture(KYCState state, MyazaKYCConfig config) {
    final idType = state.selectedIdType;
    if (idType == null) return true; // default to showing capture in progress
    final cfg = getIdTypeConfig(config.country, idType);
    return cfg?.requiresDocumentCapture ?? false;
  }

  Widget _screenForStep(KYCStep step) => switch (step) {
        KYCStep.consent         => const ConsentScreen(),
        KYCStep.idType          => const IdTypeScreen(),
        KYCStep.documentCapture => const DocumentCaptureScreen(),
        KYCStep.idInput         => const IdInputScreen(),
        KYCStep.liveness        => const LivenessScreen(),
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
      };
}
