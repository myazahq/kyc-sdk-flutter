part of 'myaza_biometric_auth.dart';

// ─── Face re-auth shell ──────────────────────────────────────────────────────
//
// How the flow is presented (route vs sheet) and dressed (system bars, colour
// scheme, the Android status strip) — the KYC flow's own shell, mirrored.

/// Android pushes a full-screen page; iOS shows a draggable bottom sheet —
/// the KYC flow's own presentation, mirrored.
Future<void> _present(
  BuildContext context,
  Widget Function(bool fullScreen) flow, {
  required bool disableClose,
  required VoidCallback? onClose,
}) {
  if (Platform.isAndroid) {
    return Navigator.of(context, rootNavigator: true)
        .push<void>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => flow(true),
        ))
        .then((_) => onClose?.call());
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: !disableClose,
    isDismissible: !disableClose,
    backgroundColor: Colors.transparent,
    useSafeArea: false,
    builder: (_) => flow(false),
  ).then((_) => onClose?.call());
}

class _BiometricAuthFlow extends ConsumerStatefulWidget {
  final String externalUserId;
  final bool isFullScreen;
  final void Function(BiometricAuthResponse result)? onAuthenticated;
  final void Function(BiometricAuthResponse result)? onFailed;
  final void Function(KYCError error)? onError;

  const _BiometricAuthFlow({
    required this.externalUserId,
    required this.isFullScreen,
    this.onAuthenticated,
    this.onFailed,
    this.onError,
  });

  @override
  ConsumerState<_BiometricAuthFlow> createState() => _BiometricAuthFlowState();
}

/// The sheet's chrome around the flow: system-bar styling, the flow's own
/// colour scheme, and the Android full-screen scaffold with its status strip
/// (the KYC flow's shell, mirrored).
Widget _shell(
  BuildContext context, {
  required Widget sheet,
  required bool fullScreen,
  required bool isDark,
  required MyazaColorScheme colorScheme,
}) {
  final overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: colorScheme.background,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
  final themed = Theme(
    data: Theme.of(context).copyWith(extensions: [colorScheme]),
    child: fullScreen
        ? AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: Scaffold(
              backgroundColor: colorScheme.background,
              body: Column(children: [
                Container(
                  height: MediaQuery.of(context).padding.top,
                  color: kycHeaderSurface(colorScheme, isDark: isDark),
                ),
                Expanded(child: SafeArea(top: false, child: sheet)),
              ]),
            ),
          )
        : AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.92,
              child: sheet,
            ),
          ),
  );
  return themed;
}
