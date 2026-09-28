import 'dart:async';
import 'dart:typed_data';

import '../config/silent_capture.dart';

/// One verification's silent-capture frames (config/silent_capture.dart).
///
/// Owned by the KYC notifier, not the liveness screen, so a retake (which
/// remounts the screen) keeps the frames already taken and can never push the
/// verification past [kSilentCaptureMax]. Everything here is best-effort and
/// silent: a frame that cannot be grabbed or uploaded is simply absent, and
/// nothing ever waits on an upload.
class SilentCaptureSession {
  SilentCaptureLedger _ledger = const SilentCaptureLedger();

  // Bumped on reset, so an upload that lands after the flow restarted is not
  // filed against the new verification.
  int _epoch = 0;

  /// The frames the server accepted, in capture order.
  List<SilentCaptureFrame> get frames => orderedSilentFrames(_ledger.frames);

  /// Whether another frame may be taken.
  bool get canTake => _ledger.canTake;

  /// A fresh verification: forget every frame, and every upload in flight.
  void reset() {
    _ledger = const SilentCaptureLedger();
    _epoch++;
  }

  /// Takes one frame: claims its place, [grab]s the JPEG, then uploads it in
  /// the background. Returns whether a frame was grabbed (the upload's own
  /// outcome is never awaited). Never throws.
  Future<bool> capture({
    required Future<Uint8List?> Function() grab,
    required Future<String> Function(Uint8List jpeg) upload,
    required String moment,
    DateTime Function() now = DateTime.now,
  }) async {
    final claim = _ledger.reserve();
    if (claim == null) return false;
    _ledger = claim.$1;
    final order = claim.$2;
    final epoch = _epoch;
    final capturedAt = now();

    Uint8List? jpeg;
    try {
      jpeg = await grab();
    } catch (_) {
      jpeg = null;
    }
    if (jpeg == null || jpeg.isEmpty) {
      if (epoch == _epoch) _ledger = _ledger.release();
      return false;
    }

    unawaited(_upload(jpeg, upload, moment, capturedAt, order, epoch));
    return true;
  }

  Future<void> _upload(
    Uint8List jpeg,
    Future<String> Function(Uint8List jpeg) upload,
    String moment,
    DateTime capturedAt,
    int order,
    int epoch,
  ) async {
    try {
      final mediaId = await upload(jpeg);
      if (epoch != _epoch) return;
      _ledger = _ledger.record(SilentCaptureFrame(
        mediaId: mediaId,
        moment: moment,
        capturedAt: capturedAt,
        order: order,
      ));
    } catch (_) {
      if (epoch == _epoch) _ledger = _ledger.release();
    }
  }
}
