import 'package:camera/camera.dart';
import 'package:video_compress/video_compress.dart';

/// Central tuning knobs for capture resolution and post-capture compression.
///
/// ## Compression strategy
///
/// We capture both a video and a still image for liveness, and both a video and
/// a still image for document. Each artifact is compressed by how much quality
/// it actually needs:
///
///   * **Video (liveness + document) — aggressive.** The video only proves the
///     capture happened; it isn't used for matching/OCR. We re-encode it with
///     [VideoQuality.LowQuality], which slashes a ~13 MB clip to well under
///     2 MB. This is the main lever for video size — it works regardless of the
///     camera resolution preset.
///   * **Selfie still — moderate.** Captured at [livenessResolution] and
///     compressed at [selfieImageQuality] (80) within
///     [selfieMinWidth]×[selfieMinHeight]. Plenty of detail for facial matching.
///   * **Document still — conservative (OCR-critical).** The server OCR has to
///     read small text (ID numbers, dates), so the document camera stays at
///     [documentResolution] (high) and the still is compressed at the higher
///     [documentImageQuality] (90) and never scaled below
///     [documentMinWidth]×[documentMinHeight].
///
/// ## Why the document camera is not `medium`
///
/// The still photo and the recorded video come from the **same**
/// [CameraController], so lowering the document preset to `medium` (~480p) would
/// also shrink the OCR still below a readable size. Instead the document camera
/// stays high and its *video* is shrunk by [VideoQuality.LowQuality] at encode
/// time. Liveness can safely run at `medium` because the selfie tolerates it.
class CaptureConfig {
  CaptureConfig._();

  // ── Camera capture resolution ──────────────────────────────────────────────

  /// Liveness/selfie camera preset. `veryHigh` is true 1080p (`high` is only
  /// 720p in the camera plugin) — the selfie carries the facial-matching quality
  /// burden, so it must stay sharp. The recorded liveness *video* is shrunk by
  /// [videoQuality] at encode time, not by lowering the camera preset.
  static const ResolutionPreset livenessResolution = ResolutionPreset.veryHigh;

  /// Document camera preset. Kept `high` so the OCR still stays sharp — the
  /// document *video* is shrunk by [videoQuality] at encode time instead.
  static const ResolutionPreset documentResolution = ResolutionPreset.high;

  // ── Video re-encode (aggressive) ────────────────────────────────────────────

  /// Quality preset passed to `VideoCompress.compressVideo`.
  static const VideoQuality videoQuality = VideoQuality.LowQuality;

  // ── Selfie still image (moderate, but kept sharp) ────────────────────────────

  static const int selfieImageQuality = 95;

  /// Cap on the selfie's longest edge (px). The capture is encoded at this size
  /// or smaller — never upscaled, never squeezed into a square — so a 1080p
  /// portrait keeps its full width for facial matching.
  static const int selfieMaxLongEdge = 1920;

  /// The face region is brightened only when its mean luminance (0–255) falls
  /// below this — fixes backlit/underexposed selfies without touching good ones.
  static const int selfieDarkThreshold = 115;

  /// Light unsharp-mask blend applied to the selfie (0 = off, 1 = full sharpen
  /// kernel). Enhances edge/feature definition; keep modest to avoid halos/noise.
  static const double selfieSharpenAmount = 0.6;

  // ── Document still image (conservative — OCR-critical) ───────────────────────

  static const int documentImageQuality = 90;
  static const int documentMinWidth = 1080;
  static const int documentMinHeight = 1080;
}
