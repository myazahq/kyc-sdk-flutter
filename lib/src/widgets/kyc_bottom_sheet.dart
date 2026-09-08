import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import 'sandbox_banner.dart';
import 'step_window.dart';
import 'kyc_progress_bar.dart';
import '../config/kyc_config.dart';
import 'powered_by.dart';
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
  /// Server-reported environment, for the sandbox strip. Null hides it.
  final String? environment;
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

  /// When set (ISO-3166 alpha-2 code), a country flag is shown beside the step
  /// title.
  final String? country;

  /// The screen content rendered below the header.
  final Widget child;

  /// When true the body is handed the exact remaining height instead of being
  /// wrapped in a scroll view, so the screen can use [Expanded]/[ListView] and
  /// own its own scrolling. This is the Flutter equivalent of the web SDK's
  /// `flex-1 min-h-0` step body — used by long list screens (country select)
  /// whose list must span the full sheet rather than a fixed fraction of it.
  final bool fillsViewport;

  /// Steps (default) or a bar on the header's bottom edge.
  final MyazaProgressStyle progressStyle;

  bool get _hasProgress => progress != null && stepCount != null;
  bool get _showBar => _hasProgress && progressStyle == MyazaProgressStyle.bar;
  bool get _showSteps =>
      _hasProgress && progressStyle == MyazaProgressStyle.steps;

  /// Whether the title block under the brand row draws anything. Steps that own
  /// their own title pass an empty one (consent, submitted) — rendering the
  /// block anyway costs an empty Text's line height plus `sm` above and below,
  /// which reads as the brand row sitting high in the header rather than
  /// centred on one line.
  bool get _hasTitleBlock =>
      title.isNotEmpty || description != null || onBack != null;

  /// Vertical space the drag handle occupies above the brand row: its own `sm`
  /// top padding plus the 4px bar. Bottom sheets draw it, full screen does not.
  static const double _dragHandleExtent = MyazaSpacing.sm + 4;

  /// Bottom padding for the brand row.
  ///
  /// Normally 0 — the title block below supplies the gap. With no title block
  /// the row is the header's only content, so it should sit on the header's
  /// centre line, and that means matching everything above it: the row's own
  /// `sm` top padding AND the drag handle. Counting only `sm` leaves the handle
  /// unbalanced and the row reads low, which is what the brand and controls
  /// looked misaligned against.
  double get _brandRowPaddingBottom {
    if (_hasTitleBlock) return 0;
    return MyazaSpacing.sm + (isFullScreen ? 0 : _dragHandleExtent);
  }

  const KycBottomSheet({
    this.environment,
    super.key,
    required this.title,
    this.description,
    this.progress,
    this.stepCount,
    this.onBack,
    this.onClose,
    this.canDismiss = true,
    this.isFullScreen = false,
    this.progressStyle = MyazaProgressStyle.steps,
    this.isDark = false,
    this.onToggleTheme,
    this.logoUrl,
    this.logoAsset,
    this.companyName,
    this.country,
    this.fillsViewport = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;

    final borderRadius = isFullScreen
        ? BorderRadius.zero
        : BorderRadius.vertical(
            top: Radius.circular(MyazaRadius.xl),
          );

    // Back navigation (Android hardware back + iOS predictive/gesture back) must
    // walk BACK through the flow one step at a time, not close the SDK. So we
    // only let the system pop the route when there's nothing to go back to — the
    // first step (onBack == null) AND the sheet is dismissible. On every other
    // step we intercept (canPop: false) and route the gesture into onBack
    // (previousStep). On the terminal / close-disabled step onBack is null and
    // canPop is false, so the gesture is swallowed — the flow can't be dismissed.
    // The explicit close (X) button force-pops past this, below.
    final bool canSystemClose = onBack == null && canDismiss;

    return PopScope(
      canPop: canSystemClose,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          onClose?.call();
          return;
        }
        onBack?.call();
      },
      // iOS's numeric keypad has NO done/return key, so a money or number
      // field could summon a keyboard the user had no way to put away again.
      // A tap on any non-interactive part of the sheet unfocuses; translucent,
      // so buttons and fields still claim their own taps first.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: borderRadius,
          ),
          child: Column(
            // max on full-screen so the column fills the Scaffold body;
            // min on sheet so it respects the outer SizedBox constraint.
            mainAxisSize: isFullScreen ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // ── Tinted header block ────────────────────────────────────────
              // Drag handle (bottom sheet) + brand + close (top line), title +
              // back arrow, then the step indicator. A subtle surface tint + a
              // full-width bottom border set the header apart from the body. The
              // drag handle lives inside the tint so the whole top of the sheet
              // is one colour.
              // Above the header so a capture step that hides the chrome
              // still says the session is not live.
              SandboxBanner(environment: environment),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: kycHeaderSurface(colors, isDark: isDark),
                  border: Border(
                    // The bar sits ON this edge and paints its own track, so
                    // the border would double it.
                    bottom: BorderSide(
                      color: colors.border,
                      width: _showBar ? 0 : 1,
                      style: _showBar ? BorderStyle.none : BorderStyle.solid,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle — only on bottom sheet
                    if (!isFullScreen) _DragHandle(color: colors.gray300),

                    // Top bar: org brand (left) + close (right), same line.
                    // See _brandRowPaddingBottom for why this is not simply 0.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        MyazaSpacing.md,
                        MyazaSpacing.sm,
                        MyazaSpacing.md,
                        _brandRowPaddingBottom,
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
                              // Explicit close: force-pop past the step-back
                              // PopScope (canPop is false on mid-flow steps, so
                              // maybePop would be swallowed there).
                              onTap: () {
                                onClose?.call();
                                final nav = Navigator.of(context);
                                if (nav.canPop()) nav.pop();
                              },
                            ),
                        ],
                      ),
                    ),

                    // Title + back arrow (close lives in the top bar)
                    if (_hasTitleBlock)
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
                    if (_showSteps)
                      _StepIndicator(
                        progress: progress!,
                        stepCount: stepCount!,
                      ),
                    if (_showSteps) const SizedBox(height: MyazaSpacing.md),
                    // Sits on the header's bottom edge in place of its border,
                    // so choosing it costs the header no height.
                    if (_showBar)
                      KycProgressBar(
                        progress: progress!,
                        stepCount: stepCount!,
                      ),
                  ],
                ),
              ),

              // Scrollable screen content. The child is constrained to at least
              // the visible viewport height so screens that bottom-align their
              // actions (e.g. a Column with MainAxisAlignment.spaceBetween, or a
              // button pinned under an Expanded) push those actions to the real
              // bottom of the sheet — while still scrolling when content overflows.
              // The keyboard inset is applied OUTSIDE the scroll view on purpose:
              // it shortens the VIEWPORT so its bottom edge sits at the top of
              // the keyboard. Flutter's focus auto-scroll targets the viewport,
              // so when the inset was inner content padding the viewport still
              // ran under the keyboard — a covered field counted as "already
              // visible" and never scrolled, leaving it (and the step's action
              // button) behind the keys.
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const topPad = MyazaSpacing.md;
                      // viewInsets is handled above; padding.bottom is already 0
                      // while the keyboard covers the home indicator.
                      // The bottom safe-area inset is NOT added here: PoweredBy
                      // sits below this viewport and owns the home-indicator
                      // clearance for the whole sheet. Adding it here too would
                      // double the gap.
                      const bottomPad = MyazaSpacing.xl;
                      final contentMinHeight =
                          (constraints.maxHeight - topPad - bottomPad)
                              .clamp(0.0, double.infinity);
                      const padding = EdgeInsets.only(
                        left: MyazaSpacing.md,
                        right: MyazaSpacing.md,
                        top: topPad,
                        bottom: bottomPad,
                      );

                      // Fill mode: give the screen the remaining height directly so
                      // it can flex/scroll internally. No outer scroll view, since
                      // that would hand the child an unbounded height and make
                      // Expanded impossible.
                      //
                      // The bottom inset is deliberately NOT applied here: a list
                      // that stops short of the screen edge looks clipped on iOS.
                      // The viewport runs to the bottom and the screen's own list
                      // carries the home-indicator inset as CONTENT padding, so
                      // rows scroll fully clear of it. (The keyboard inset is
                      // already handled by the Padding above.)
                      if (fillsViewport) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            left: MyazaSpacing.md,
                            right: MyazaSpacing.md,
                            top: topPad,
                          ),
                          child: child,
                        );
                      }

                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        // Pulling the list down collapses the keyboard — the one
                        // gesture every user already tries.
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: padding,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: contentMinHeight),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Vendor attribution — a sibling of the Expanded body, so it stays
              // pinned while a long step scrolls under it.
              const PoweredBy(),
            ],
          ),
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

  /// Base circle size, before text scaling.
  static const double _circle = 26;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final active = _activeIndex;

    // Grow the circle with the system text size, or the number inside it clips
    // the moment a user turns the OS font scale up. Capped at 1.4: past that
    // the row matters less than the step content below it.
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    final size = (_circle * scale).roundToDouble();
    final badge = (13 * scale).roundToDouble();
    final step = (active + 1).clamp(1, stepCount);

    // ONE label for the whole row: a screen reader walking ten unlabelled
    // circles and announcing a bare "6" says nothing about how far through the
    // flow that is.
    return Semantics(
      container: true,
      label: 'Step $step of $stepCount',
      value: '$step of $stepCount',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.md),
          // Measured rather than assumed, so a flow collapses on a narrow phone
          // and stays whole on a wide one instead of both obeying one cap.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slots = windowedSteps(
                stepCount,
                active,
                maxCircles: fitStepCircles(constraints.maxWidth, size),
              );
              return Row(
                children: [
                  for (int position = 0;
                      position < slots.length;
                      position++) ...[
                    if (slots[position] == kStepEllipsis)
                      // Collapsed run, sized to the circle's height so the
                      // connectors either side stay on one centre line and the
                      // chain reads as continuous rather than broken in two.
                      SizedBox(
                        height: size,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '···',
                              textScaler: TextScaler.noScaling,
                              style: GoogleFonts.karla(
                                fontSize: 13,
                                letterSpacing: 1,
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      _StepDot(
                        index: slots[position],
                        size: size,
                        badgeSize: badge,
                        dotState: slots[position] < active
                            ? _StepDotState.completed
                            : slots[position] == active
                                ? _StepDotState.active
                                : _StepDotState.upcoming,
                        colors: colors,
                      ),
                    if (position < slots.length - 1)
                      Expanded(
                        child: _StepConnector(
                          completed: slots[position] != kStepEllipsis &&
                              slots[position] < active,
                          colors: colors,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final _StepDotState dotState;
  final MyazaColorScheme colors;
  final double size;
  final double badgeSize;

  const _StepDot({
    required this.index,
    required this.dotState,
    required this.colors,
    required this.size,
    required this.badgeSize,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = dotState == _StepDotState.completed;
    final isActive = dotState == _StepDotState.active;
    final filled = isCompleted || isActive;

    return SizedBox(
      width: size,
      height: size,
      // Clip.none so the badge may straddle the circle's edge.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? colors.primary : Colors.transparent,
              border: Border.all(
                color: filled ? colors.primary : colors.primary200,
                width: 1.5,
              ),
            ),
            child: Center(
              // The NUMBER stays, completed or not. A check alone says a step is
              // done but not WHICH step — and once the row is windowed
              // ("1 ··· 5 6 7 ··· 10") that is precisely what the numbers answer.
              child: Text(
                '${index + 1}',
                textScaler: TextScaler.noScaling,
                style: GoogleFonts.karla(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : colors.textMuted,
                ),
              ),
            ),
          ),
          // Completion rides as a badge tucked onto the circle's corner. The
          // ring is WHITE — the same colour as the number inside the circle —
          // because the badge sits on the circle, not on the page.
          if (isCompleted)
            Positioned(
              top: -3,
              right: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Static, not a scheme field: MyazaColorScheme carries
                  // successBg but the solid success colour lives on MyazaColors
                  // and is the same in both themes.
                  color: MyazaColors.success,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(
                  LucideIcons.check,
                  size: (badgeSize * 0.6).roundToDouble(),
                  color: Colors.white,
                ),
              ),
            ),
        ],
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
        constraints: const BoxConstraints(minWidth: 6),
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

  /// Whether a logo URL points at an SVG (extension check, query-safe).
  static bool _isSvgUrl(String url) =>
      (Uri.tryParse(url)?.path ?? url).toLowerCase().endsWith('.svg');

  Widget _logo() {
    final url = logoUrl;
    if (url != null) {
      // Browsers render SVG logos in <img>, but Image.network cannot decode
      // SVG at all — an org whose logo is an .svg (common: the brand import
      // picks up site favicons) silently lost its logo here while the web SDK
      // showed it. Route SVG URLs through flutter_svg instead.
      if (_isSvgUrl(url)) {
        return SvgPicture.network(
          url,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      }
      return Image.network(
        url,
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
            LucideIcons.x,
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
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap!();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
