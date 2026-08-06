import 'package:flutter/material.dart';

// ─── Staggered reveal ─────────────────────────────────────────────────────────
//
// Fades and lifts children in sequence so a screen assembles rather than
// appearing all at once. 50ms between items, which is the middle of the 30–50ms
// band that reads as deliberate without feeling slow.
//
// Counts as ONE animation for the "1–2 animated elements per view" rule: it's a
// single grouped entrance, not per-element choreography competing for
// attention.
//
// Reduced-motion renders everything immediately at rest.

class StaggeredReveal extends StatefulWidget {
  final List<Widget> children;

  /// Gap between each child's start.
  final Duration interval;

  /// How far each child travels up as it fades in.
  final double offset;

  const StaggeredReveal({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 50),
    this.offset = 10,
  });

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  static const _itemDuration = Duration(milliseconds: 260);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _itemDuration +
        widget.interval * (widget.children.length - 1).clamp(0, 20),
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // NOTE: do NOT gate this on "the setting changed". Reduce-motion is off for
    // most users, so a `reduce != _reduced` guard is false on first build and
    // the animation never starts — leaving the controller at 0, which for a
    // fade-in means every child renders fully TRANSPARENT.
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value < 1) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Window this child occupies within the shared controller.
  Animation<double> _slot(int index) {
    final total = _c.duration!.inMilliseconds;
    final start = (widget.interval.inMilliseconds * index) / total;
    final end =
        ((widget.interval.inMilliseconds * index) + _itemDuration.inMilliseconds) /
            total;
    return CurvedAnimation(
      parent: _c,
      // ease-out for entering.
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
          curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _slot(i).value;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  // Transform only — never animate layout properties.
                  offset: Offset(0, widget.offset * (1 - t)),
                  child: child,
                ),
              );
            },
            child: widget.children[i],
          ),
      ],
    );
  }
}
