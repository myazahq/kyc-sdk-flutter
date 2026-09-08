import 'dart:async';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/address_state.dart' show AddressStreetView;
import '../../config/map_frame.dart';
import '../../config/street_view_fov.dart';
import '../../config/theme.dart';
import '../../utils/map_tiles.dart' show MapLatLng, mapSurfaceHeight;
import '../../widgets/myaza_button.dart';
import '../../widgets/sticky_actions.dart';
import 'street_view_chrome.dart';

// ─── Framed Street View ──────────────────────────────────────────────────────
//
// Street View on mobile, via OUR hosted /embed/street-view page in a WebView,
// the same model (and the same app grant) as FramedMapPicker. The page renders
// the panorama and streams the current view; THIS widget owns the framing
// chrome, the frame-subtended fov maths and the capture decision, so hosted,
// embedded and native applicants meet the identical instrument. Mirrors the
// web SDK's FramedStreetView and the RN twin; keep the three in lockstep.
//
// A page that never says sv-ready (blocked script, refused grant, no
// coverage) hands the step to the photo fallback via [onUnavailable].

class FramedStreetView extends StatefulWidget {
  final String frameUrl;
  final MapLatLng pin;
  final ValueChanged<AddressStreetView> onCaptured;

  /// The applicant would rather add their own photo.
  final VoidCallback onSkip;

  /// streetView 'required': the skip affordance is removed while coverage
  /// exists (no-coverage still falls back, the client-UX gate only).
  final bool hideSkip;

  /// No coverage, no grant, or no page: fall back to the photo.
  final VoidCallback onUnavailable;

  const FramedStreetView({
    super.key,
    required this.frameUrl,
    required this.pin,
    required this.onCaptured,
    required this.onSkip,
    required this.onUnavailable,
    this.hideSkip = false,
  });

  @override
  State<FramedStreetView> createState() => _FramedStreetViewState();
}

class _FramedStreetViewState extends State<FramedStreetView> {
  WebViewController? _controller;
  bool _ready = false;
  Timer? _readyTimer;
  StreetViewPov? _latestPov;

  @override
  void initState() {
    super.initState();
    _readyTimer = Timer(kMapFrameReadyTimeout, () {
      if (!_ready) _unavailable();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final src = buildStreetViewFrameSrc(
      widget.frameUrl,
      pin: widget.pin,
      theme: isDark ? 'dark' : 'light',
    );
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        kMapFrameChannel,
        onMessageReceived: (message) => _onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onWebResourceError: (_) => _unavailable()),
      )
      ..loadRequest(Uri.parse(src));
    setState(() => _controller = controller);
  }

  void _onMessage(String data) {
    switch (parseStreetViewFrameMessage(data)) {
      case StreetViewReady():
        _readyTimer?.cancel();
        if (mounted) setState(() => _ready = true);
      case StreetViewUnavailable():
        _unavailable();
      case final StreetViewPov pov:
        _latestPov = pov;
      case null:
        break;
    }
  }

  bool _gone = false;
  void _unavailable() {
    _readyTimer?.cancel();
    if (_gone || !mounted) return;
    _gone = true;
    widget.onUnavailable();
  }

  void _capture(Size viewport) {
    final pov = _latestPov;
    if (pov == null) return;
    // The promise on screen is the FRAME: the captured fov is the slice it
    // subtends of the reported view, same maths and geometry as the web framer.
    final frame = streetViewFrameRect(viewport);
    widget.onCaptured(captureStreetViewFrame(pov, frame.width, viewport.width));
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final height = mapSurfaceHeight(MediaQuery.sizeOf(context));
    final controller = _controller;
    return LayoutBuilder(builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, height);
      return StickyActions(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MyazaRadius.md),
                child: Stack(children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: colors.backgroundSecondary,
                      child: controller == null
                          ? const SizedBox.shrink()
                          : WebViewWidget(
                      controller: controller,
                      // Android: inside StickyActions' scroll view the
                      // scroll view wins every vertical drag in the gesture
                      // arena and the map stops dead; an eager recogniser
                      // claims the touch for the WebView (S24, 2026-09-07).
                      gestureRecognizers: const {
                        Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      },
                    ),
                    ),
                  ),
                  if (!_ready)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_ready) const Positioned.fill(child: StreetViewChrome()),
                ]),
              ),
            ),
            if (_ready) ...[
              const SizedBox(height: MyazaSpacing.sm),
              Text(
                'Drag to look around until your gate or front door sits inside the frame.',
                textAlign: TextAlign.center,
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
        actions: Row(children: [
          if (!widget.hideSkip) ...[
            Expanded(
              child: MyazaButton.outline(label: 'Skip', onPressed: widget.onSkip),
            ),
            const SizedBox(width: MyazaSpacing.sm),
          ],
          Expanded(
            child: MyazaButton(
              label: 'Use this view',
              onPressed: _ready ? () => _capture(viewport) : null,
            ),
          ),
        ]),
      );
    });
  }
}
