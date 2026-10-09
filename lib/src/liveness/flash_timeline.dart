// WHEN each flash colour came on, measured from the start of the liveness
// recording.
//
// The server re-reads the recording to check the flash for itself. Without
// these times it has to FIND the sequence in the video, which works when the
// reflection is strong and guesses when it is faint. With them it looks in the
// right place and only has to decide whether the colour was there.
//
// They are a claim like the sequence itself: the server uses them to know
// where to look, never as evidence that anything was reflected.
//
// A recorder takes a moment to write its first frame after it is asked to
// start, so the server allows for an offset.
//
// Mirrors the web SDK (liveness/flash-timeline.ts) and the React Native SDK
// (liveness/flashTimeline.ts). Change all three together.

int? _recordingStartedAt;

/// The liveness recorder went live (or stopped: pass null). Epoch milliseconds.
void markRecordingStart(int? at) => _recordingStartedAt = at;

/// The current time on the clock the recording start was marked with.
int flashClockNow() => DateTime.now().millisecondsSinceEpoch;

/// The colour-on times as ms from the start of the recording, or null when
/// there is no recording to measure from or a colour never ran. One whole,
/// rising list or nothing: half a timeline would point the server at the wrong
/// colours.
List<int>? flashOnsets(List<int> onAt, int colours, {int? startedAt, bool useMarked = true}) {
  final start = startedAt ?? (useMarked ? _recordingStartedAt : null);
  if (start == null || onAt.length != colours || colours == 0) return null;
  final onsets = [for (final at in onAt) at - start];
  for (var i = 0; i < onsets.length; i++) {
    if (onsets[i] < 0) return null;
    if (i > 0 && onsets[i] <= onsets[i - 1]) return null;
  }
  return onsets;
}
