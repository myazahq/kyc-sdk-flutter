import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../liveness/blur_budget.dart';

/// Whether the surfaces over the liveness camera may blur what is behind
/// them. False on a phone that cannot afford it, and when the person asked
/// for high contrast: the surfaces are then flat and opaque.
class LivenessBlurScope extends InheritedWidget {
  const LivenessBlurScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  /// True outside a scope: the review and the loading screen draw over a
  /// still picture, which costs nothing to blur.
  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LivenessBlurScope>();
    return (scope?.enabled ?? true) && !MediaQuery.highContrastOf(context);
  }

  @override
  bool updateShouldNotify(LivenessBlurScope old) => old.enabled != enabled;
}

/// Watches how long the frames under it take to draw while the live camera is
/// on screen, and turns the blur off for good once the phone falls behind
/// (liveness/blur_budget.dart).
class LivenessBlurBudget extends StatefulWidget {
  const LivenessBlurBudget({super.key, required this.child});

  final Widget child;

  @override
  State<LivenessBlurBudget> createState() => _LivenessBlurBudgetState();
}

class _LivenessBlurBudgetState extends State<LivenessBlurBudget> {
  final _budget = BlurBudget();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    var ended = false;
    for (final timing in timings) {
      // The raster time: the blur is drawn there, not in build.
      if (_budget.add(timing.rasterDuration)) ended = true;
    }
    if (ended && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      LivenessBlurScope(enabled: _budget.affordable, child: widget.child);
}
