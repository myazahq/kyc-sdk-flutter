import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';

/// Back and close for the full-screen camera, which has no header to hold
/// them. Drawn by the shell, which owns what each of them does.
class LivenessImmersiveControls extends StatelessWidget {
  const LivenessImmersiveControls({super.key, this.onBack, this.onClose});

  final VoidCallback? onBack;
  final VoidCallback? onClose;

  /// Where the middle of each button sits from its edge of the screen. Fixed,
  /// so the picture does not move when the tap area grows around it.
  static const double _centreInset = 32;

  @override
  Widget build(BuildContext context) {
    // 44 on iOS, 48 on Android: each platform's own minimum.
    final target =
        defaultTargetPlatform == TargetPlatform.android ? 48.0 : 44.0;
    final top = MediaQueryData.fromView(View.of(context)).viewPadding.top +
        8 -
        (target - 44) / 2;
    final side = _centreInset - target / 2;
    return Stack(
      children: [
        if (onBack != null)
          Positioned(
            top: top,
            left: side,
            child: _RoundButton(
              // The long arrow the header's own back button draws.
              icon: MyazaIcons.moveLeft,
              iconSize: 22,
              label: 'Back',
              target: target,
              onTap: onBack!,
            ),
          ),
        if (onClose != null)
          Positioned(
            top: top,
            right: side,
            child: _RoundButton(
              icon: MyazaIcons.x,
              iconSize: 20,
              label: 'Close',
              target: target,
              onTap: onClose!,
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.target,
    required this.onTap,
  });

  final MyazaIconData icon;

  /// The size the header draws this glyph at, so it is the same control.
  final double iconSize;
  final String label;

  /// The side of the square that takes the tap.
  final double target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Semantics(
      button: true,
      label: label,
      // The children are excluded so the button is read once, by its name.
      // That also drops the ink well's own tap, so it is given here: without
      // it a screen reader could find the button and not press it.
      onTap: onTap,
      excludeSemantics: true,
      // 40 to look at, as in the header; the whole square takes the tap.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: Material(
              color: colors.backgroundSecondary,
              shape: CircleBorder(side: BorderSide(color: colors.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox.square(
                  dimension: 40,
                  child: MyazaIcon(
                    icon,
                    size: iconSize,
                    color: colors.textDark.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
