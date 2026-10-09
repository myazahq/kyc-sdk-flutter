import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The person's OWN colours, handed down by the shell while the liveness step
/// has the screen.
///
/// The step is lit (light, at full brightness) from the moment the camera
/// opens until the person leaves it, so the screen lights their face. That is
/// for the camera. The review after it has nothing left to light, so it reads
/// this and goes back to the flow's own theme while the step stays latched.
class LivenessOwnTheme extends InheritedWidget {
  const LivenessOwnTheme({
    super.key,
    required this.scheme,
    required super.child,
  });

  final MyazaColorScheme scheme;

  /// Builds [builder] in the person's own theme, or in the surrounding one
  /// when no shell provided it.
  ///
  /// The colours travel there over a fifth of a second. On a dark flow the
  /// camera is light and the review dark, and switching between them in one
  /// frame read as the screen blinking off.
  static Widget wrap(BuildContext context, WidgetBuilder builder) {
    final own =
        context.dependOnInheritedWidgetOfExactType<LivenessOwnTheme>()?.scheme;
    if (own == null) return Builder(builder: builder);
    final lit = context.myazaColors;
    final theme = Theme.of(context);
    Widget themed(MyazaColorScheme scheme) => Theme(
          data: theme.copyWith(extensions: [scheme]),
          child: Builder(builder: builder),
        );
    if (MediaQuery.disableAnimationsOf(context)) return themed(own);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, _) => themed(lit.lerp(own, t)),
    );
  }

  @override
  bool updateShouldNotify(LivenessOwnTheme old) => old.scheme != scheme;
}
