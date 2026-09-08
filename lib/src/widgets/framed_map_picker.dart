import 'dart:async';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/map_frame.dart';
import '../config/theme.dart';
import '../utils/map_tiles.dart' show MapLatLng;
import 'map_pin_picker.dart';

// ─── Framed map picker ───────────────────────────────────────────────────────
//
// Google Maps on mobile, via OUR hosted /embed/map page in a WebView (the OkHi
// model: the map runs on the hosted origin, on Myaza's own key). Mirrors the
// web SDK's FramedMapPicker and the RN twin: a page that never says `ready`
// falls back to the dependency-free OSM picker. A null [frameUrl] IS the OSM
// picker.

class FramedMapPicker extends StatefulWidget {
  /// The server-minted page URL; null ⇒ the OSM picker outright.
  final String? frameUrl;
  final MapLatLng? value;
  final ValueChanged<MapLatLng> onChange;
  final MapLatLng defaultCenter;
  final int defaultZoom;
  final double height;

  /// Corner rounding; 0 where a parent already shapes the frame (the review
  /// card rounds its top corners only).
  final double? cornerRadius;
  final Widget? overlay;

  const FramedMapPicker({
    super.key,
    required this.frameUrl,
    required this.value,
    required this.onChange,
    required this.defaultCenter,
    required this.defaultZoom,
    this.height = 300,
    this.cornerRadius,
    this.overlay,
  });

  @override
  State<FramedMapPicker> createState() => _FramedMapPickerState();
}

class _FramedMapPickerState extends State<FramedMapPicker> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;
  Timer? _readyTimer;
  MapLatLng? _lastFromFrame;

  @override
  void initState() {
    super.initState();
    final frameUrl = widget.frameUrl;
    if (frameUrl == null) {
      _failed = true;
      return;
    }
    _readyTimer = Timer(kMapFrameReadyTimeout, () {
      if (!_ready) _fail();
    });
    // Deferred to the first frame: the src needs the theme (a BuildContext).
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(frameUrl));
  }

  void _load(String frameUrl) {
    if (!mounted) return;
    final colors = context.myazaColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = colors.primary.toARGB32().toRadixString(16).padLeft(8, '0');
    final src = buildMapFrameSrc(
      frameUrl,
      center: widget.value ?? widget.defaultCenter,
      zoom: widget.defaultZoom,
      hasPin: widget.value != null,
      theme: isDark ? 'dark' : 'light',
      primaryColor: '#${primary.substring(2)}',
    );
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        kMapFrameChannel,
        onMessageReceived: (message) => _onMessage(message.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (_) => _fail(),
      ))
      ..loadRequest(Uri.parse(src));
    setState(() => _controller = controller);
  }

  void _onMessage(String data) {
    switch (parseMapFrameMessage(data)) {
      case MapFrameReady():
        _readyTimer?.cancel();
        if (mounted) setState(() => _ready = true);
      case MapFrameFailed():
        _fail();
      case MapFramePin(:final pin):
        _lastFromFrame = pin;
        widget.onChange(pin);
      case null:
        break;
    }
  }

  void _fail() {
    _readyTimer?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  @override
  void didUpdateWidget(FramedMapPicker old) {
    super.didUpdateWidget(old);
    // An external recentre moves the map; never echo back the page's own pin.
    final value = widget.value;
    if (value == null || !_ready || samePin(_lastFromFrame, value)) return;
    if (old.value != null && samePin(old.value, value)) return;
    _controller?.runJavaScript(centerCommandScript(value));
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return MapPinPicker(
        value: widget.value,
        onChange: widget.onChange,
        defaultCenter: widget.defaultCenter,
        defaultZoom: widget.defaultZoom,
        height: widget.height,
        overlay: widget.overlay,
        cornerRadius: widget.cornerRadius,
      );
    }
    final colors = context.myazaColors;
    final controller = _controller;
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius ?? MyazaRadius.md),
        child: Stack(children: [
          Positioned.fill(
            child: ColoredBox(
              color: colors.backgroundSecondary,
              child: controller == null
                  ? const SizedBox.shrink()
                  : WebViewWidget(
                      controller: controller,
                      // Android: the scroll view above wins every vertical
                      // drag, so an eager recogniser claims the touch for
                      // the WebView (S24, 2026-09-07).
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
          // Bottom centre, as the built-in picker places it (unpositioned, it sat top-left).
          if (widget.overlay != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MyazaSpacing.md,
              child: Center(child: widget.overlay!),
            ),
        ]),
      ),
    );
  }
}
