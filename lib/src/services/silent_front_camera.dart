import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'image_service.dart';

// ─── Silent capture: one headless front-camera frame ─────────────────────────
//
// Taken on the document review (config/silent_capture.dart): the rear camera
// has been released and the person is looking at the photo they just took.
// The front camera is opened with no preview widget, given a moment for
// exposure to settle, and one frame is taken, then the camera is closed.
//
//   • iOS reads a frame off the image stream: `takePicture` goes through
//     AVCapturePhotoOutput, which plays the shutter sound.
//   • Android takes a still: CameraX makes no sound, and a still avoids a
//     YUV conversion.
//
// Everything is best-effort: no front camera, a device that is still busy, a
// timeout or any camera error returns null, and the flow never waits on it
// beyond the review it runs behind.

/// How long the front camera runs before the frame is taken.
const Duration kSilentFrontSettle = Duration(milliseconds: 900);

/// The longest a grab may take, opening and closing included.
const Duration kSilentFrontTimeout = Duration(seconds: 6);

/// Takes one JPEG from the front camera, or null. [cancelled] is polled
/// between steps: once it returns true the camera is closed and nothing is
/// returned (the screen needs the camera back, or has gone).
Future<Uint8List?> grabSilentFrontFrame({required bool Function() cancelled}) async {
  CameraController? controller;
  try {
    return await _grab(cancelled, (c) => controller = c).timeout(kSilentFrontTimeout);
  } catch (_) {
    return null;
  } finally {
    final c = controller;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {/* closing anyway */}
      try {
        await c.dispose();
      } catch (_) {/* already gone */}
    }
  }
}

Future<Uint8List?> _grab(
  bool Function() cancelled,
  void Function(CameraController) opened,
) async {
  final cameras = await availableCameras();
  final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front);
  if (front.isEmpty || cancelled()) return null;

  final controller = CameraController(
    front.first,
    ResolutionPreset.medium,
    enableAudio: false,
    imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.jpeg,
  );
  opened(controller);
  await controller.initialize();
  if (cancelled()) return null;

  if (Platform.isIOS) {
    CameraImage? latest;
    await controller.startImageStream((image) => latest = image);
    await Future<void>.delayed(kSilentFrontSettle);
    await controller.stopImageStream();
    final image = latest;
    if (image == null || cancelled() || image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return processSelfieFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      bgra: true,
      mirror: false,
    );
  }

  await Future<void>.delayed(kSilentFrontSettle);
  if (cancelled()) return null;
  final file = await controller.takePicture();
  final bytes = await file.readAsBytes();
  if (cancelled() || bytes.isEmpty) return null;
  return processSelfieStreamStill(bytes);
}
