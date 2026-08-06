import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The **Flutter camera-plugin** document preview — iOS's normal path, and
/// Android's fallback when the native [DocumentCamera] fails to start.
///
/// Why not plain `CameraPreview` on Android? On the camerax backend the preview
/// follows the LIVE device orientation (accelerometer): when
/// handlesCropAndRotation is false — true on many phones, incl. the Galaxy S24 —
/// the plugin re-queries display.getRotation() on every orientation event and
/// rotates the preview widget to match. Holding the phone tilted/flat over a
/// document (the natural capture pose) makes the sensor read "landscape", so the
/// feed visibly rotates a second or two in. No display/orientation lock stops
/// it: the plugin reads the physical sensor, not the app's UI orientation, and
/// the capture itself is already upright (imageCapture uses the locked UI
/// rotation) — only the preview drifts.
///
/// So on Android this renders the RAW camera texture (`Texture(textureId:
/// controller.cameraId)` — exactly what the plugin wraps) at a fixed rotation
/// derived from the sensor orientation, which is a constant and cannot drift,
/// and hides the engine's warmup + capture reconfiguration behind a cover.
///
/// All of that is workaround, which is why Android now prefers the native
/// camera: there the preview texture is upright from the first frame and a still
/// reconfigures nothing, so none of the machinery below is needed.
class DocumentPluginPreview extends StatefulWidget {
  final CameraController controller;

  /// True while a still capture is in flight. On Android, stopping the video
  /// recording + firing takePicture reconfigures the camera surface, which
  /// briefly drops the engine's texture rotation (a sideways flash) before the
  /// still-review screen takes over — so we re-raise the warmup cover to hide it.
  final bool isCapturing;

  const DocumentPluginPreview(this.controller, {super.key, this.isCapturing = false});

  @override
  State<DocumentPluginPreview> createState() => _DocumentPluginPreviewState();
}

class _DocumentPluginPreviewState extends State<DocumentPluginPreview> {
  // On Android the engine rotates the camera texture upright ~1s AFTER bind, and
  // there's no Dart-visible event at that instant. Until then the raw texture is
  // the un-rotated (sideways) sensor frame, so hold a warmup cover — styled
  // exactly like the pre-init placeholder — over the preview for a short settle
  // window, then fade it away. The user only ever sees the upright feed. iOS is
  // rotation-stable from the first frame, so it reveals immediately.
  static const _settleDelay = Duration(milliseconds: 900);

  bool _settled = !Platform.isAndroid;
  Timer? _settleTimer;

  /// The cover is shown while the texture hasn't settled upright OR a capture is
  /// reconfiguring the surface — both Android-only sources of a sideways flash.
  bool get _covered => Platform.isAndroid && (!_settled || widget.isCapturing);

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _settleTimer = Timer(_settleDelay, () {
        if (mounted) setState(() => _settled = true);
      });
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final buffer = controller.value.previewSize ?? const Size(1280, 720);

    // iOS: CameraPreview is stable and rotation-correct. Android: DON'T use
    // CameraPreview — the plugin's rotation math lands the rear document feed a
    // constant 90° off. The engine already rotates the raw TEXTURE upright, so
    // render it directly and add NO rotation (any extra RotatedBox just
    // double-rotates it back to sideways — every earlier attempt's bug).
    // previewSize is the LANDSCAPE sensor buffer, but the presented texture is
    // rotated to PORTRAIT, and a Texture stretches to its box — so the box must
    // be portrait (height×width swapped) or the upright feed stretches sideways.
    final feed = ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: buffer.height,
          height: buffer.width,
          child: Platform.isAndroid
              ? Texture(textureId: controller.cameraId)
              : CameraPreview(controller),
        ),
      ),
    );

    // iOS never needs a cover; on Android it's up during warmup and re-raised
    // for the capture reconfiguration.
    if (!Platform.isAndroid) return feed;

    return Stack(
      fit: StackFit.expand,
      children: [
        feed,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _covered ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              color: const Color(0xFF111111),
              child: Center(
                child: CircularProgressIndicator(
                  color: context.myazaColors.primary,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
