import 'package:flutter/material.dart';

/// Renders an Android native CameraX preview texture (the liveness recorder's
/// or the document camera's) upright and cover-fit.
///
/// CameraX's `Preview` use case delivers an already UPRIGHT, display-oriented
/// image into the SurfaceTexture — verified on device: adding any `RotatedBox`
/// knocked the picture sideways. So this rotates nothing and mirrors nothing
/// (CameraX already renders the front camera mirrored, selfie-style; adding a
/// flip un-mirrored it). All it does is cover-fit using the PORTRAIT aspect —
/// the reported buffer dimensions are the sensor's landscape numbers, so they're
/// swapped for display, which is what stops the feed looking stretched.
///
/// This is the whole reason the native path has no rotation bug: there is no
/// orientation math here to drift, unlike the plugin's preview, which re-queries
/// the display rotation on every accelerometer event.
class NativeCameraPreview extends StatelessWidget {
  final int textureId;

  /// Preview buffer size as reported by the native side, in the sensor's
  /// native (landscape) orientation.
  final int bufferWidth;
  final int bufferHeight;

  const NativeCameraPreview({
    super.key,
    required this.textureId,
    required this.bufferWidth,
    required this.bufferHeight,
  });

  @override
  Widget build(BuildContext context) {
    final rawW = (bufferWidth > 0 ? bufferWidth : 1280).toDouble();
    final rawH = (bufferHeight > 0 ? bufferHeight : 720).toDouble();
    // Display is portrait → the narrower edge is the width.
    final dispW = rawW < rawH ? rawW : rawH;
    final dispH = rawW < rawH ? rawH : rawW;

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: dispW,
        height: dispH,
        child: Texture(textureId: textureId),
      ),
    );
  }
}
