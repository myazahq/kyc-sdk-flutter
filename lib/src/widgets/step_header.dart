import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'country_flag.dart';

// ─── Step header ──────────────────────────────────────────────────────────────

class StepHeader extends StatelessWidget {
  /// Screen title rendered in Space Grotesk bold.
  final String title;

  /// Optional subtitle rendered in Karla below the title.
  final String? description;

  /// Called when the back arrow is tapped.
  /// Pass null to hide the back arrow (e.g. first step, processing, result).
  final VoidCallback? onBack;

  /// Optional trailing widget shown in the header row (e.g. a close button).
  final Widget? trailing;

  /// When set (ISO-3166 alpha-2 code), a small circular country flag is shown
  /// beside the title.
  final String? country;

  const StepHeader({
    super.key,
    required this.title,
    this.description,
    this.onBack,
    this.trailing,
    this.country,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Title row ─────────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              _BackButton(onTap: onBack!, colors: colors),
              const SizedBox(width: MyazaSpacing.sm),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(title, style: text.heading2),
                  ),
                  if (country != null) ...[
                    const SizedBox(width: MyazaSpacing.sm),
                    MyazaCountryFlag(country: country, size: 20),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),

        // ── Description ────────────────────────────────────────────────────
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Padding(
            padding: EdgeInsets.only(
              left: onBack != null
                  ? _BackButton.size + MyazaSpacing.sm
                  : 0,
            ),
            child: Text(
              description!,
              style: text.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Back button ──────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  /// Footprint reserved in the header row (used for description alignment).
  /// Smaller than the old filled circle so the borderless icon sits closer to
  /// the title; a larger invisible tap target is kept inside.
  static const double size = 28;

  final VoidCallback onTap;
  final MyazaColorScheme colors;

  const _BackButton({required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      // Transparent, generous tap target around a fine borderless icon.
      child: SizedBox(
        width: size,
        height: 40,
        child: Center(
          child: Icon(
            // Elongated left arrow (longer shaft than arrow_back_rounded).
            Icons.keyboard_backspace_rounded,
            size: 24,
            color: colors.textDark.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

// ─── Press-scale wrapper ──────────────────────────────────────────────────────
//
// Wraps any widget in a tap-to-scale micro-animation.
// The child shrinks slightly on press-down and springs back on release.

class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressScale({required this.child, this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap!(); },
      onTapCancel: ()  => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
