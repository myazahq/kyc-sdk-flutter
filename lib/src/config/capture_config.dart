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

  /// Document camera preset. `veryHigh` (~1080p) — bumped from `high` (~720p),
  /// which was the real cause of soft document captures: at 720p the fine detail
  /// in ID numbers/dates simply wasn't there, so raising JPEG quality alone
  /// couldn't recover it. 1080p doubles the linear detail (matches the selfie
  /// path) so OCR has sharp text to read. The document *video* is still shrunk
  /// by [videoQuality] at encode time, so the higher preset doesn't bloat it.
  static const ResolutionPreset documentResolution = ResolutionPreset.veryHigh;

  // ── Video re-encode (aggressive) ────────────────────────────────────────────

  /// Quality preset passed to `VideoCompress.compressVideo`. `video_compress`
  /// only exposes discrete presets (no percentage knob), so "make the liveness
  /// clip clearer" maps to one step up — `LowQuality` → `MediumQuality` — which
  /// raises the encode bitrate/resolution (a clearer clip at a modestly larger
  /// file, still well within the upload budget).
  static const VideoQuality videoQuality = VideoQuality.MediumQuality;

  // ── Selfie still image (moderate, but kept sharp) ────────────────────────────

  /// Starting JPEG quality for the selfie. The encoder steps this down (never the
  /// resolution) until the file fits [selfieMaxBytes], so facial detail is kept
  /// while the size stays under the upload budget.
  static const int selfieImageQuality = 88;

  /// Upper bound on the encoded selfie file size. Kept under ~1 MB so uploads are
  /// fast and well within the server's media limit, while staying high enough for
  /// reliable liveness + facial comparison.
  static const int selfieMaxBytes = 950 * 1024;

  /// Minimum quality the size-fit loop will drop to before it resorts to scaling
  /// down — keeps the face from going soft/blocky.
  static const int selfieMinQuality = 70;

  /// Cap on the selfie's longest edge (px). 1080 keeps ample facial detail for
  /// matching while keeping files small; never upscaled, never squeezed square.
  static const int selfieMaxLongEdge = 1080;

  /// The face region is brightened only when its mean luminance (0–255) falls
  /// below this — fixes backlit/underexposed selfies without touching good ones.
  static const int selfieDarkThreshold = 115;

  /// Light unsharp-mask blend applied to the selfie (0 = off, 1 = full sharpen
  /// kernel). Enhances edge/feature definition; keep modest to avoid halos/noise.
  static const double selfieSharpenAmount = 0.6;

  // ── Document still image (conservative — OCR-critical) ───────────────────────

  /// Higher quality (was 90) to preserve fine text edges now that the capture is
  /// 1080p — pairs with the resolution bump for a clearer document.
  static const int documentImageQuality = 95;

  /// Don't downscale the document below ~1080p — keeps OCR text legible. Raised
  /// alongside [documentResolution] so the sharper capture isn't shrunk away.
  static const int documentMinWidth = 1440;
  static const int documentMinHeight = 1440;
}
