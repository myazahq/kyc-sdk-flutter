import 'dart:convert';

import '../utils/map_tiles.dart' show MapLatLng;
import 'map_frame.dart' show kMapFrameSource;

// ─── The framed STREET VIEW page (the entrance framing) ──────────────────────
//
// Same origin, same APP grant, sibling page: /embed/street-view lives beside
// /embed/map and the grant unlocks the key for either, so the SDK DERIVES its
// URL from the server-minted mapsFrameUrl by swapping the path (the two pages
// ship together with this SDK, and the coupling is recorded on both sides).
// The page is deliberately dumb: it renders the panorama and streams the
// current view (`sv-pov`) over the same channel the map uses; the framing
// chrome, the frame-subtended fov maths and the capture decision stay in the
// SDK. Mirror of the web and RN SDKs' street-view halves; keep in lockstep.
//
//   page -> app: { source: 'myaza-map', type: 'sv-ready' | 'sv-unavailable' }
//                { source: 'myaza-map', type: 'sv-pov', panoId, heading, pitch, viewFov }

/// The street-view page's URL derived from the map frame's, or null when the
/// frame URL is not the page family this SDK knows.
String? streetViewFrameUrlOf(String mapsFrameUrl) {
  final url = Uri.tryParse(mapsFrameUrl);
  if (url == null || !url.path.endsWith('/embed/map')) return null;
  return url
      .replace(
        path: url.path.replaceFirst(RegExp(r'/embed/map$'), '/embed/street-view'),
      )
      .toString();
}

/// The full page URL: the derived page (carrying the signed APP grant and
/// `mode=app`) plus the pin the panorama should look from. No `origin`: an
/// app has none, and the page proves that instead.
String buildStreetViewFrameSrc(
  String frameUrl, {
  required MapLatLng pin,
  String? theme,
}) {
  final url = Uri.parse(frameUrl);
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'lat': '${pin.lat}',
    'lng': '${pin.lng}',
    if (theme != null) 'theme': theme,
  }).toString();
}

sealed class StreetViewFrameMessage {
  const StreetViewFrameMessage();
}

class StreetViewReady extends StreetViewFrameMessage {
  const StreetViewReady();
}

class StreetViewUnavailable extends StreetViewFrameMessage {
  const StreetViewUnavailable();
}

/// The panorama's current view, as the page streams it.
class StreetViewPov extends StreetViewFrameMessage {
  final String panoId;
  final double heading;
  final double pitch;
  final double viewFov;

  const StreetViewPov({
    required this.panoId,
    required this.heading,
    required this.pitch,
    required this.viewFov,
  });
}

/// Validate-and-drop for the street-view page's messages.
StreetViewFrameMessage? parseStreetViewFrameMessage(String data) {
  Object? decoded;
  try {
    decoded = jsonDecode(data);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['source'] != kMapFrameSource) return null;
  switch (decoded['type']) {
    case 'sv-ready':
      return const StreetViewReady();
    case 'sv-unavailable':
      return const StreetViewUnavailable();
    case 'sv-pov':
      final panoId = decoded['panoId'];
      final heading = decoded['heading'];
      final pitch = decoded['pitch'];
      final viewFov = decoded['viewFov'];
      if (panoId is! String ||
          panoId.isEmpty ||
          heading is! num ||
          pitch is! num ||
          viewFov is! num ||
          !heading.isFinite ||
          !pitch.isFinite ||
          !viewFov.isFinite) {
        return null;
      }
      return StreetViewPov(
        panoId: panoId,
        heading: heading.toDouble(),
        pitch: pitch.toDouble(),
        viewFov: viewFov.toDouble(),
      );
  }
  return null;
}
