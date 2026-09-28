import 'package:flutter/widgets.dart';

import '../config/bright_screen.dart';
import '../liveness/screen_brightness.dart';

// ─── Holds the screen bright while the selfie camera is on ────────────────────
//
// Wraps the flow. [active] says whether the flow is lit right now (see
// livenessBrightScreenActive); this widget turns that into the platform call,
// and gives the screen back whenever the app leaves the foreground, the flag
// drops, or the flow itself goes away. Restoring is idempotent, so every one of
// those paths may call it without tracking what the others did.

class BrightScreenBoost extends StatefulWidget {
  const BrightScreenBoost({
    super.key,
    required this.active,
    required this.child,
    this.boost,
  });

  final bool active;
  final Widget child;

  /// Injectable for tests; one is created per flow otherwise.
  final ScreenBrightnessBoost? boost;

  @override
  State<BrightScreenBoost> createState() => _BrightScreenBoostState();
}

class _BrightScreenBoostState extends State<BrightScreenBoost>
    with WidgetsBindingObserver {
  late final ScreenBrightnessBoost _boost =
      widget.boost ?? ScreenBrightnessBoost();
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(BrightScreenBoost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _sync();
  }

  void _sync() {
    final want = brightScreenBoostWanted(
      active: widget.active,
      lifecycle: _lifecycle,
    );
    if (want) {
      _boost.raise();
    } else {
      _boost.restore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The flow closing (or failing) must never leave the screen pinned.
    _boost.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
