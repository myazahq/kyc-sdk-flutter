import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/id_types.dart';
import '../config/theme.dart';
import 'step_header.dart';

// ─── Bottom sheet container ───────────────────────────────────────────────────
//
// Presentational wrapper used by both presentation modes:
//   isFullScreen = false  →  iOS bottom sheet (drag handle, rounded top)
//   isFullScreen = true   →  Android full-screen page (no handle, flat edges)
//
// The parent (_KycFlowWidget) owns routing logic and passes title / progress /
// navigation callbacks down as parameters.

class KycBottomSheet extends StatelessWidget {
  final String title;
  final String? description;

  /// 0.0–1.0 progress fraction for the step indicator.
  /// Pass null to hide the indicator (processing / result screens).
  final double? progress;

  /// Total number of steps in the current session.
  /// Required alongside [progress] to render the segmented indicator.
  final int? stepCount;

  /// Called when the back arrow is tapped. Null hides the arrow.
  final VoidCallback? onBack;

  /// Called when the sheet is closed/popped.
  final VoidCallback? onClose;

  /// When false the sheet cannot be dismissed by dragging or back gesture.
  final bool canDismiss;

  /// True on Android — hides the drag handle and removes rounded corners.
  final bool isFullScreen;

  /// Whether the current theme is dark (used to show correct toggle icon).
  final bool isDark;

  /// Called when the user taps the theme-toggle button.
  final VoidCallback? onToggleTheme;

  /// Org logo network URL (resolved from `appearance.logo`, including the
  /// `'default'` server-config case). Rendered in the persistent brand bar.
  final String? logoUrl;

  /// Org logo local asset path (fallback when [logoUrl] is null).
  final String? logoAsset;

  /// Org/company name shown beside the logo in the brand bar.
  final String? companyName;

  /// When set, a country flag is shown beside the step title.
  final Country? country;

  /// The screen content rendered below the header.
  final Widget child;

  const KycBottomSheet({
    super.key,
    required this.title,
    this.description,
    this.progress,
    this.stepCount,
    this.onBack,
    this.onClose,
    this.canDismiss = true,
    this.isFullScreen = false,
    this.isDark = false,
    this.onToggleTheme,
    this.logoUrl,
    this.logoAsset,
    this.companyName,
    this.country,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    final borderRadius = isFullScreen
        ? BorderRadius.zero
        : const BorderRadius.vertical(
            top: Radius.circular(MyazaRadius.xl),
          );

    return PopScope(
      canPop: canDismiss,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) onClose?.call();
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: borderRadius,
        ),
        child: Column(
          // max on full-screen so the column fills the Scaffold body;
          // min on sheet so it respects the outer SizedBox constraint.
          mainAxisSize:
              isFullScreen ? MainAxisSize.max : MainAxisSize.min,
          children: [
            // ── Tinted header block ────────────────────────────────────────
            // Drag handle (bottom sheet) + brand + close (top line), title +
            // back arrow, then the step indicator. A subtle surface tint + a
            // full-width bottom border set the header apart from the body. The
            // drag handle lives inside the tint so the whole top of the sheet
            // is one colour.
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: kycHeaderSurface(colors, isDark: isDark),
                border: Border(
                  bottom: BorderSide(color: colors.border, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle — only on bottom sheet
                  if (!isFullScreen) _DragHandle(color: colors.gray300),

                  // Top bar: org brand (left) + close (right), same line
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MyazaSpacing.md,
                      MyazaSpacing.sm,
                      MyazaSpacing.md,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: (logoUrl != null || logoAsset != null)
                              ? _BrandBar(
                                  logoUrl: logoUrl,
                                  logoAsset: logoAsset,
                                  companyName: companyName,
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (onToggleTheme != null) ...[
                          _ThemeToggleButton(
                            isDark: isDark,
                            onToggle: onToggleTheme!,
                          ),
                          if (canDismiss)
                            const SizedBox(width: MyazaSpacing.xs),
                        ],
                        // Hide the close button entirely when the sheet can't be
                        // dismissed (terminal step or disableClose) — rather than
                        // showing a greyed, dead button.
                        if (canDismiss)
                          _CloseButton(
                            isDark: isDark,
                            onTap: () {
                              Navigator.of(context).maybePop();
                              onClose?.call();
                            },
                          ),
                      ],
                    ),
                  ),

                  // Title + back arrow (close lives in the top bar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MyazaSpacing.md,
                      MyazaSpacing.sm,
                      MyazaSpacing.md,
                      MyazaSpacing.sm,
                    ),
                    child: StepHeader(
                      title: title,
                      description: description,
                      onBack: onBack,
                      country: country,
                    ),
                  ),

                  // Step indicator
                  if (progress != null && stepCount != null)
                    _StepIndicator(
                      progress: progress!,
                      stepCount: stepCount!,
                    ),
                  if (progress != null && stepCount != null)
                    const SizedBox(height: MyazaSpacing.md),
                ],
              ),
            ),

            // Scrollable screen content. The child is constrained to at least
            // the visible viewport height so screens that bottom-align their
            // actions (e.g. a Column with MainAxisAlignment.spaceBetween, or a
            // button pinned under an Expanded) push those actions to the real
            // bottom of the sheet — while still scrolling when content overflows.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const topPad = MyazaSpacing.md;
                  final bottomPad = MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      MyazaSpacing.xl;
                  final contentMinHeight =
                      (constraints.maxHeight - topPad - bottomPad)
                          .clamp(0.0, double.infinity);
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: MyazaSpacing.md,
                      right: MyazaSpacing.md,
                      top: topPad,
                      bottom: bottomPad,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: contentMinHeight),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step indicator ───────────────────────────────────────────────────────────
//
// Renders N numbered circles connected by thin lines.
//   • Upcoming  → outlined circle, muted number
//   • Active    → filled primary circle, white number
//   • Completed → filled primary circle, animated checkmark (spring pop)
//
// progress = (currentIndex + 1) / stepCount, so:
//   activeIndex = round(progress * stepCount) - 1

enum _StepDotState { upcoming, active, completed }

class _StepIndicator extends StatelessWidget {
  final double progress; // 0.0–1.0
  final int stepCount;

  const _StepIndicator({required this.progress, required this.stepCount});

  int get _activeIndex => (progress * stepCount).round() - 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final active = _activeIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
      child: Row(
        children: [
          for (int i = 0; i < stepCount; i++) ...[
            _StepDot(
              index: i,
              dotState: i < active
                  ? _StepDotState.completed
                  : i == active
                      ? _StepDotState.active
                      : _StepDotState.upcoming,
              colors: colors,
            ),
            if (i < stepCount - 1)
              Expanded(
                child: _StepConnector(
                  completed: i < active,
                  colors: colors,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final _StepDotState dotState;
  final MyazaColorScheme colors;

  const _StepDot({
    required this.index,
    required this.dotState,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = dotState == _StepDotState.completed;
    final isActive    = dotState == _StepDotState.active;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isCompleted || isActive) ? colors.primary : Colors.transparent,
        border: Border.all(
          color: (isCompleted || isActive) ? colors.primary : colors.primary200,
          width: 1.5,
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.45, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeIn,
                ),
              ),
              child: child,
            ),
          ),
          child: isCompleted
              ? const Icon(
                  Icons.check_rounded,
                  key: ValueKey('check'),
                  size: 14,
                  color: Colors.white,
                )
              : Text(
                  '${index + 1}',
                  key: const ValueKey('num'),
                  style: GoogleFonts.karla(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : colors.textMuted,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool completed;
  final MyazaColorScheme colors;

  const _StepConnector({required this.completed, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        height: 2,
        decoration: BoxDecoration(
          color: completed ? colors.primary : colors.primary200,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ─── Brand bar ────────────────────────────────────────────────────────────────
//
// Persistent org branding shown at the top of the sheet on every step: a small
// circular logo avatar + company name, left-aligned. Mirrors the web SDK's
// header brand. Hidden entirely when there's no logo (the parent only renders
// it when a logoUrl/logoAsset is present); a broken logo image collapses to
// nothing via errorBuilder.

class _BrandBar extends StatelessWidget {
  final String? logoUrl;
  final String? logoAsset;
  final String? companyName;

  const _BrandBar({this.logoUrl, this.logoAsset, this.companyName});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    // No outer padding — the parent top-bar row supplies it and pairs this with
    // the close button on the same line.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            // Explicit ClipOval — a Container's decoration clip doesn't reliably
            // crop a cover-fit child to a circle, so a square logo would show as
            // a squircle. SizedBox.expand gives the image tight bounds to cover.
            child: ClipOval(
              child: SizedBox.expand(child: _logo()),
            ),
          ),
          if (companyName != null && companyName!.isNotEmpty) ...[
            const SizedBox(width: MyazaSpacing.sm),
            Flexible(
              child: Text(
                companyName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textDark,
                ),
              ),
            ),
          ],
        ],
      );
  }

  Widget _logo() {
    if (logoUrl != null) {
      return Image.network(
        logoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    if (logoAsset != null) {
      return Image.asset(
        logoAsset!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─── Internal sub-widgets ─────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final Color color;

  const _DragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.sm),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(MyazaRadius.full),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isDark;

  const _CloseButton({this.onTap, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final enabled = onTap != null;

    return _PressScale(
      onTap: onTap,
      // Borderless ghost icon with a generous, transparent tap target.
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: enabled
                ? colors.textDark.withValues(alpha: 0.8)
                : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ─── Theme toggle button (header) ─────────────────────────────────────────────
//
// Compact borderless ghost icon in the top bar (sun in dark mode → switch to
// light; moon in light mode → switch to dark). Matches the close button style.

class _ThemeToggleButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;

  const _ThemeToggleButton({required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return _PressScale(
      onTap: onToggle,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            size: 20,
            color: colors.textDark.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

// ─── Press-scale wrapper ──────────────────────────────────────────────────────

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
