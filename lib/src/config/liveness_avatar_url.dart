import '../liveness/liveness_types.dart';
import '../utils/resolve_url.dart';

// ─── Where the gesture animations come from ───────────────────────────────────
//
// They used to be four GIFs inside this package — 5.7 MB, shipped to every
// device whatever the workflow asked for, for a badge that is on screen for a
// few seconds of the liveness step. They are served by the API instead
// (`/api/kyc/assets/liveness/<gesture>.<ext>`), precached when liveness opens,
// and held in Flutter's image cache from then on.
//
// WEBP here, GIF on React Native — the one place the two SDKs deliberately
// differ. Flutter decodes animated WebP natively, so it takes the file that is
// a tenth of the size; React Native decodes only GIF animation on iOS and
// depends on the host app's Fresco configuration for WebP on Android. The
// server keeps both encodings for exactly this reason.
//
// Nothing here throws. A device that never gets the file shows the gesture icon
// the avatar has always fallen back to, with the instruction text above it.

const String _livenessAvatarExtension = 'webp';

const List<LivenessChallenge> livenessAvatarGestures = <LivenessChallenge>[
  LivenessChallenge.nod,
  LivenessChallenge.turn,
  LivenessChallenge.blink,
  LivenessChallenge.smile,
];

String _gestureName(LivenessChallenge challenge) => switch (challenge) {
      LivenessChallenge.nod => 'nod',
      LivenessChallenge.turn => 'turn',
      LivenessChallenge.blink => 'blink',
      LivenessChallenge.smile => 'smile',
    };

/// The served URL for one gesture's animation, or null when the key is
/// malformed — which is a real error everywhere else in the SDK and merely a
/// missing cartoon here, so it must never reach a build().
String? livenessAvatarUrl(
  LivenessChallenge challenge,
  String apiKey, {
  String? devUrl,
}) {
  try {
    final base = resolveBaseUrl(apiKey, devUrl: devUrl);
    return '$base/api/kyc/assets/liveness/'
        '${_gestureName(challenge)}.$_livenessAvatarExtension';
  } catch (_) {
    return null;
  }
}

/// Every gesture's URL, for precaching at the start of the liveness step.
///
/// All four, because which gestures a session asks for is randomised per
/// session; together they are under 350 KB.
List<String> livenessAvatarUrls(String apiKey, {String? devUrl}) {
  final urls = <String>[];
  for (final gesture in livenessAvatarGestures) {
    final url = livenessAvatarUrl(gesture, apiKey, devUrl: devUrl);
    if (url != null) urls.add(url);
  }
  return urls;
}
