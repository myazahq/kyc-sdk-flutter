import 'scope.dart';

// ─── Silent capture: the pure rules ──────────────────────────────────────────
//
// Up to THREE unposed photos of the applicant, taken during DOCUMENT CAPTURE
// only, never on the liveness step. The document is shot with the rear
// camera, so on the review (rear camera released, the person looking at the
// photo they just took) the SDK briefly opens the FRONT camera with no preview
// and takes one frame (services/silent_front_camera.dart): no prompt, no UI,
// no sound. A reviewer sees who was holding the ID.
//
// Mirror of the web and React Native SDKs' silent-capture module; keep the
// rules identical across all three:
//   • the workflow flag `silentCapture` is ON unless it is exactly `false`;
//   • document capture only, so it never runs on a scoped flow;
//   • at most three frames per verification, however many retakes;
//   • slots are 1-based, in capture order, with no gaps: a frame whose upload
//     failed is simply absent and the next one takes its number.
//
// Wire contract (server-side, fixed): each frame is uploaded as media type
// `silent_capture` (JPEG), submitted as `mediaIds.silentCapture1..3`, and
// described in `metadata.device.silentCapture` as
// `[{ slot, moment, capturedAt }]`.

/// The most frames one verification may carry.
const int kSilentCaptureMax = 3;

/// The upload media type the server files these frames under.
const String kSilentCaptureMediaType = 'silent_capture';

/// When a frame was taken. Values are the wire vocabulary; only document
/// capture takes frames now (older builds also sent `'selfie'`).
abstract final class SilentCaptureMoment {
  static const document = 'document';
}

/// Whether silent capture applies to a flow. [flag] is the workflow (or
/// consumer) `silentCapture` value, where null means on; [scope] is the
/// workflow scope, where null (or an unknown value) means the full flow.
bool silentCaptureApplies({required bool? flag, required String? scope}) {
  if (flag == false) return false;
  return configScope(scope) == null;
}

/// One frame the server accepted.
class SilentCaptureFrame {
  final String mediaId;
  final String moment;
  final DateTime capturedAt;

  /// Capture order, from [SilentCaptureLedger.reserve]. Slots are assigned
  /// from this at submission, so a failed upload never leaves a gap.
  final int order;

  const SilentCaptureFrame({
    required this.mediaId,
    required this.moment,
    required this.capturedAt,
    required this.order,
  });
}

/// Frames taken so far in one verification. Immutable; every change returns a
/// new ledger. [inFlight] counts frames grabbed but not yet uploaded, so two
/// grabs racing an upload can never exceed the cap.
class SilentCaptureLedger {
  final List<SilentCaptureFrame> frames;
  final int inFlight;
  final int nextOrder;

  const SilentCaptureLedger({
    this.frames = const [],
    this.inFlight = 0,
    this.nextOrder = 1,
  });

  /// Whether another frame may be taken.
  bool get canTake => frames.length + inFlight < kSilentCaptureMax;

  /// Claims the next frame. Returns null at the cap; otherwise the new ledger
  /// and the claimed capture order.
  (SilentCaptureLedger, int)? reserve() {
    if (!canTake) return null;
    return (
      SilentCaptureLedger(frames: frames, inFlight: inFlight + 1, nextOrder: nextOrder + 1),
      nextOrder,
    );
  }

  /// A claimed frame uploaded. A duplicate order, or a frame past the cap, is
  /// ignored: the ledger never holds more than [kSilentCaptureMax].
  SilentCaptureLedger record(SilentCaptureFrame frame) {
    final settled = inFlight > 0 ? inFlight - 1 : 0;
    final duplicate = frames.any((f) => f.order == frame.order || f.mediaId == frame.mediaId);
    if (duplicate || frames.length >= kSilentCaptureMax) {
      return SilentCaptureLedger(frames: frames, inFlight: settled, nextOrder: nextOrder);
    }
    return SilentCaptureLedger(
      frames: [...frames, frame],
      inFlight: settled,
      nextOrder: nextOrder,
    );
  }

  /// A claimed frame could not be grabbed or uploaded; its place is freed.
  SilentCaptureLedger release() => SilentCaptureLedger(
        frames: frames,
        inFlight: inFlight > 0 ? inFlight - 1 : 0,
        nextOrder: nextOrder,
      );
}

/// The uploaded frames in capture order, capped at [kSilentCaptureMax].
List<SilentCaptureFrame> orderedSilentFrames(List<SilentCaptureFrame> frames) {
  final sorted = [...frames]..sort((a, b) => a.order.compareTo(b.order));
  return sorted.take(kSilentCaptureMax).toList(growable: false);
}

/// `mediaIds` entries for the submission: `silentCapture1..N`, 1-based.
Map<String, String> silentCaptureMediaIds(List<SilentCaptureFrame> frames) {
  final ordered = orderedSilentFrames(frames);
  return {
    for (var i = 0; i < ordered.length; i++) 'silentCapture${i + 1}': ordered[i].mediaId,
  };
}

/// `metadata.device.silentCapture` entries, slot-aligned with
/// [silentCaptureMediaIds]. Empty when nothing was uploaded.
List<Map<String, dynamic>> silentCaptureDeviceEntries(List<SilentCaptureFrame> frames) {
  final ordered = orderedSilentFrames(frames);
  return [
    for (var i = 0; i < ordered.length; i++)
      {
        'slot': i + 1,
        'moment': ordered[i].moment,
        'capturedAt': ordered[i].capturedAt.toUtc().toIso8601String(),
      },
  ];
}

/// Adds the frames' description to a device block, leaving it untouched when
/// no frame was uploaded. A null block becomes one holding only the frames.
Map<String, dynamic>? withSilentCaptureDevice(
  Map<String, dynamic>? device,
  List<SilentCaptureFrame> frames,
) {
  final entries = silentCaptureDeviceEntries(frames);
  if (entries.isEmpty) return device;
  return {...?device, 'silentCapture': entries};
}
