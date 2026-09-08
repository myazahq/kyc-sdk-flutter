import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/biometric_auth.dart';
import '../config/kyc_config.dart';
import '../config/theme.dart';
import '../utils/resolve_url.dart';
import '../providers/kyc_provider.dart';
import '../providers/kyc_state.dart';
import '../providers/theme_provider.dart';
import '../screens/liveness_screen.dart';
import '../services/api_service.dart';
import 'kyc_bottom_sheet.dart';
import 'myaza_button.dart';
import 'myaza_kyc_widget.dart' show kycFlowOverrides;

part 'biometric_auth_screens.dart';
part 'biometric_auth_shell.dart';

// ─── MyazaBiometricAuth ──────────────────────────────────────────────────────
//
// Returning-user face re-authentication ("prove it's still you"). Mirrors the
// web and RN SDKs' MyazaBiometricAuth: a verified user re-authenticates with a
// live selfie matched 1:1 against their enrollment reference (no gov-DB call,
// no re-KYC). Hosts the SDK's REAL liveness screen inside its own
// ProviderScope, parked on the liveness step: the screen's Continue advances
// the notifier to `submitted` (the scope's step order), which is the
// hand-over — the uploaded selfie's mediaId is read off the state and sent to
// /biometric/authenticate. The submitted screen is never built, so nothing
// ever calls /verify.

class MyazaBiometricAuth {
  MyazaBiometricAuth._();

  static Future<void> show({
    required BuildContext context,
    required String apiKey,
    required String externalUserId,
    String? devUrl,
    String livenessMode = 'gestures',
    /// Colours in the flash sequence (2..5, default 4), as on RN.
    int? flashSequenceLength,
    MyazaKYCAppearance? appearance,
    bool disableClose = false,
    void Function(BiometricAuthResponse result)? onAuthenticated,
    void Function(BiometricAuthResponse result)? onFailed,
    void Function(KYCError error)? onError,
    VoidCallback? onClose,
  }) async {
    detectEnvironment(apiKey);
    // The liveness screen reads exactly the keys a KYC flow's config carries;
    // the scope parks the step order on consent → liveness → submitted, and
    // the flow only ever builds the middle one. `country` is required by the
    // full flow but nothing on this path reads it.
    final config = MyazaKYCConfig(
      apiKey: apiKey,
      devUrl: devUrl,
      country: 'NG',
      scope: 'biometric-authentication',
      livenessMode: livenessMode,
      flashSequenceLength: flashSequenceLength ?? 4,
      appearance: appearance,
      disableClose: disableClose,
      userId: externalUserId,
    );
    MyazaRadius.applyScale(appearance?.borderRadius);
    applyBrandFonts(
      body: appearance?.fontFamily,
      heading: appearance?.headingFontFamily,
    );
    final overrides = kycFlowOverrides(config, null);
    Widget flow(bool fullScreen) => ProviderScope(
          overrides: overrides,
          child: _BiometricAuthFlow(
            externalUserId: externalUserId,
            isFullScreen: fullScreen,
            onAuthenticated: onAuthenticated,
            onFailed: onFailed,
            onError: onError,
          ),
        );

    return _present(context, flow,
        disableClose: disableClose, onClose: onClose);
  }
}

enum _View { intro, capture, authenticating, result }

class _BiometricAuthFlowState extends ConsumerState<_BiometricAuthFlow> {
  _View _view = _View.intro;
  BiometricAuthResponse? _result;
  String? _errorMessage;
  bool _inFlight = false;

  void _startCapture() {
    ref.read(kYCNotifierProvider.notifier)
      ..clearSelfie()
      ..goToStep(KYCStep.liveness);
    setState(() {
      _view = _View.capture;
      _result = null;
      _errorMessage = null;
    });
  }

  Future<void> _authenticate(String selfieMediaId) async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() => _view = _View.authenticating);
    final config = ref.read(kycConfigProvider);
    try {
      final result =
          await ref.read(kYCNotifierProvider.notifier).api.authenticate(
                externalUserId: widget.externalUserId,
                selfieMediaId: selfieMediaId,
                livenessMode: config.livenessMode,
              );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.authenticated) {
        widget.onAuthenticated?.call(result);
      } else {
        widget.onFailed?.call(result);
      }
    } catch (err) {
      final kyc = mapBiometricAuthError(err);
      if (mounted) setState(() => _errorMessage = kyc.message);
      widget.onError?.call(kyc);
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _view = _View.result);
    }
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // The hand-over: the liveness screen's Continue moved the notifier past
    // the liveness step with the selfie uploaded.
    ref.listen(kYCNotifierProvider.select((s) => s.currentStep), (_, step) {
      if (_view != _View.capture || step == KYCStep.liveness) return;
      final selfie = ref.read(kYCNotifierProvider).mediaIds.selfie;
      if (selfie != null) _authenticate(selfie);
    });

    final config = ref.watch(kycConfigProvider);
    final mode = ref.watch(kycThemeModeProvider);
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final colorScheme = isDark ? MyazaColorScheme.dark : MyazaColorScheme.light;
    final dismissBlocked = config.disableClose || _view == _View.authenticating;

    final sheet = KycBottomSheet(
      title: switch (_view) {
        _View.capture => 'Face check',
        _View.authenticating => "Verifying it's you",
        _ => "Verify it's you",
      },
      description: _view == _View.capture
          ? 'Follow the prompts, then hold still for the photo.'
          : null,
      onBack: _view == _View.capture
          ? () => setState(() => _view = _View.intro)
          : null,
      onClose: dismissBlocked ? null : _close,
      canDismiss: !dismissBlocked,
      isFullScreen: widget.isFullScreen,
      isDark: isDark,
      progressStyle: config.progressStyle,
      companyName: config.appearance?.companyName,
      child: switch (_view) {
        _View.intro => _Intro(onStart: _startCapture),
        _View.capture => LivenessScreen(onError: widget.onError),
        _View.authenticating => const _Authenticating(),
        _View.result => _Result(
            result: _result,
            errorMessage: _errorMessage,
            onRetry: _startCapture,
            onClose: _close,
          ),
      },
    );

    final themed = _shell(
      context,
      sheet: sheet,
      fullScreen: widget.isFullScreen,
      isDark: isDark,
      colorScheme: colorScheme,
    );
    return PopScope(canPop: !dismissBlocked, child: themed);
  }
}
