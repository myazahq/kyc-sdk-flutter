import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/liveness_avatar_url.dart';
import 'package:myaza_kyc_sdk_flutter/src/liveness/liveness_types.dart';

// The gesture animations are FETCHED, not bundled — 5.7 MB of GIF used to ship
// in every integrator's app for a badge the liveness step shows for seconds.
//
// Pinned here: the URL matches the route the server serves, the builder never
// throws (a malformed key costs a cartoon, not a build), and this SDK asks for
// WEBP where React Native asks for GIF. That difference is deliberate — Flutter
// decodes animated WebP natively at a tenth of the size — and it is the kind of
// thing a later "let us make the two SDKs consistent" tidy-up would undo.

const live = 'pk_live_0123456789abcdef0123456789abcdef';

void main() {
  test('points at the served route, per gesture', () {
    expect(
      livenessAvatarUrl(LivenessChallenge.nod, live),
      'https://trust.myaza.app/api/kyc/assets/liveness/nod.webp',
    );
    expect(
      livenessAvatarUrl(LivenessChallenge.smile, live),
      'https://trust.myaza.app/api/kyc/assets/liveness/smile.webp',
    );
  });

  test('asks for webp, which React Native deliberately does not', () {
    expect(livenessAvatarUrl(LivenessChallenge.turn, live)!.endsWith('.webp'), isTrue);
  });

  test('honours devUrl on a development key', () {
    expect(
      livenessAvatarUrl(LivenessChallenge.blink, 'pk_dev_abc',
          devUrl: 'http://192.168.1.5:3001'),
      'http://192.168.1.5:3001/api/kyc/assets/liveness/blink.webp',
    );
  });

  test('returns null rather than throwing on a malformed key', () {
    expect(livenessAvatarUrl(LivenessChallenge.nod, 'not-a-key'), isNull);
  });

  test('precache covers all four, because the session picks at random', () {
    final urls = livenessAvatarUrls(live);
    expect(urls, hasLength(4));
    expect(urls.every((u) => u.startsWith('https://trust.myaza.app/api/kyc/')), isTrue);
  });

  test('precache yields nothing on a malformed key', () {
    expect(livenessAvatarUrls('not-a-key'), isEmpty);
  });
}
