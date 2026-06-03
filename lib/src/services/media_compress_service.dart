import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

import '../config/capture_config.dart';

/// Post-capture compression for videos and still images.
///
/// Compression strategy (see [CaptureConfig] for the knobs):
///   * **Video** — aggressive. Re-encoded with [CaptureConfig.videoQuality]
///     ([VideoQuality.LowQuality]); a ~13 MB clip drops to well under 2 MB.
///   * **Selfie still** — moderate. JPEG quality 80 within 1080×1080.
///   * **Document still** — conservative (OCR-critical). JPEG quality 90, never
///     scaled below 1080 px, so small text (ID numbers, dates) stays readable.
///
/// Both `video_compress` and `flutter_image_compress` run their heavy work on
/// native platform threads, so awaiting them does not block the Dart UI
/// isolate — callers should still show their existing loading state.

// ─── Debug size logging ─────────────────────────────────────────────────────

void _logSize(String label, int beforeBytes, int afterBytes) {
  if (!kDebugMode) return;
  String kb(int b) => '${(b / 1024).toStringAsFixed(1)} KB';
  final pct = beforeBytes > 0
      ? (100 - afterBytes / beforeBytes * 100).toStringAsFixed(0)
      : '0';
  debugPrint('[MyazaKYC] $label: ${kb(beforeBytes)} → ${kb(afterBytes)} (-$pct%)');
}

// ─── Video ──────────────────────────────────────────────────────────────────

/// Compresses the recorded video file at [inputPath] for upload and returns the
/// compressed bytes. Falls back to the original file's bytes when compression
/// is unavailable or returns null. [label] is used only for debug logging.
Future<Uint8List> compressVideoToBytes(String inputPath, {String label = 'video'}) async {
  final originalBytes = await File(inputPath).readAsBytes();
  try {
    final info = await VideoCompress.compressVideo(
      inputPath,
      quality: CaptureConfig.videoQuality,
      deleteOrigin: false,
    );
    final outPath = info?.file?.path ?? info?.path;
    if (outPath == null) {
      _logSize('$label (compress returned null — using original)',
          originalBytes.length, originalBytes.length);
      return originalBytes;
    }
    final compressed = await File(outPath).readAsBytes();
    if (compressed.isEmpty) return originalBytes;
    _logSize(label, originalBytes.length, compressed.length);
    // Guard against the rare case where re-encoding produced a larger file.
    return compressed.length < originalBytes.length ? compressed : originalBytes;
  } catch (_) {
    // Best-effort: a failed compression must not block the upload.
    return originalBytes;
  }
}

// ─── Still images ─────────────────────────────────────────────────────────────
//
// The SELFIE still is handled by `processSelfieImage` in image_service.dart
// (orientation + exposure lift + sharp encode), not here — it needs pixel-level
// brightness work that flutter_image_compress can't do.

/// Compresses a DOCUMENT still — conservative/OCR-critical (quality 90, never
/// scaled below 1080 px). Returns the original bytes unchanged if compression
/// fails so OCR never receives nothing.
Future<Uint8List> compressDocumentImage(Uint8List bytes, {String label = 'document still'}) async {
  try {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      quality: CaptureConfig.documentImageQuality,
      minWidth: CaptureConfig.documentMinWidth,
      minHeight: CaptureConfig.documentMinHeight,
    );
    if (out.isEmpty) return bytes;
    _logSize(label, bytes.length, out.length);
    return out;
  } catch (_) {
    return bytes;
  }
}
