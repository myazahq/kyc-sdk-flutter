import 'dart:ui' show Color;

// ─── What the flash overlay shows ─────────────────────────────────────────────
//
// The flash check compares the face under each colour against a NEUTRAL frame
// taken just before it, and assumes the colour ADDS light to that frame. With
// the screen behind the overlay dark, it did. With a light (white) screen, the
// baseline is already lit from every channel, so a red flash takes blue and
// green AWAY and the reflection reads backwards.
//
// So while a sequence runs, the neutral frames are black: the overlay stays up
// between colours and paints black, and the only light the screen adds is the
// colour under test. Outside a sequence the overlay shows nothing. This holds
// whatever theme the flow is in, and whether or not the bright screen is on.

/// The neutral frame between colours while a flash sequence runs.
const Color kFlashBaselineColor = Color(0xFF000000);

/// The colour the fullscreen flash overlay paints, or null for none.
///
/// [flashColor] is the colour under test (null between colours);
/// [sequenceRunning] is true only while a sequence is measuring.
Color? flashOverlayColor({
  required Color? flashColor,
  required bool sequenceRunning,
}) {
  if (flashColor != null) return flashColor;
  return sequenceRunning ? kFlashBaselineColor : null;
}
