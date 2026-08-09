import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'nfc_scan_painter.dart';

/// The NFC scan illustration, ported 1:1 from the web SDK's
/// `NfcScanIllustration` — same 320×240 geometry, same three beats: a
/// document with a CHIP, a phone held over it, a FIELD between them. The web
/// component is the design source of truth; every coordinate in the painter
/// matches it digit for digit so the builder preview (web) and this live
/// screen stay the same picture. Change the web one first, then mirror.
///
/// Same footprint as the web too: full width up to 384 (`max-w-sm`), 320:240.
class NfcScanIllustration extends StatefulWidget {
  const NfcScanIllustration({super.key});

  @override
  State<NfcScanIllustration> createState() => _NfcScanIllustrationState();
}

class _NfcScanIllustrationState extends State<NfcScanIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same rule as the web's reduced-motion media query: the pulse stops and
    // the arcs stay visible at their base opacity.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: AspectRatio(
          aspectRatio: 320 / 240,
          child: CustomPaint(
            painter: NfcScanPainter(
              colors: context.myazaColors,
              pulse: _controller,
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      ),
    );
  }
}
