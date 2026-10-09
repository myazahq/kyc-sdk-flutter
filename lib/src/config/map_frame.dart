import 'dart:convert';

import '../utils/map_tiles.dart' show MapLatLng;

// The street-view half of the protocol lives next door (200-line rule),
// re-exported so every importer of this file keeps working.
export 'street_view_frame.dart';

// ─── The framed map's protocol ───────────────────────────────────────────────
//
// The framed Google-map picker's client half, for a WebView (the OkHi model):
// the SDK loads OUR hosted /embed/map page TOP-LEVEL in a WebView and talks to
// it over a JavaScript channel. A mirror of the web SDK's lib/map-frame.ts and
// the RN SDK's — keep the three in lockstep.
//
// Message shapes (add-only; the page mirrors them):
//   page -> app: { source: 'myaza-map', type: 'ready' | 'failed' }
//                { source: 'myaza-map', type: 'pin', lat, lng }
//   app -> page: window.__myazaMapCommand(JSON of
//                { source: 'myaza-sdk', type: 'center', lat, lng, zoom? })

const String kMapFrameSource = 'myaza-map';
const String kMapParentSource = 'myaza-sdk';

/// The JavaScript channel the page posts to. Registered by the picker.
const String kMapFrameChannel = 'MyazaMap';

/// How long to wait for `ready` before falling back to the OSM picker.
// 20 seconds: the hosted page is rendered per request and then loads Google's
// script, and from a phone on mobile data that measured over 8 seconds often
// enough that the map fell back to the built-in picker while the real one was
// still on its way (production, 2026-10-04). The three SDKs keep one value.
const Duration kMapFrameReadyTimeout = Duration(seconds: 20);

/// Whether a WebView resource error means the PAGE failed to load. A map
/// requests hundreds of tiles and cancels many of them as it is dragged, and
/// each of those is a resource error too; treating one as a failed page
/// swapped a working Google map for the built-in picker mid-drag. Only an
/// error on the page itself counts, and only before the page said it was
/// ready. An unknown answer (null) on a page that is not ready counts, since
/// the alternative is a blank rectangle.
bool frameLoadFailed({required bool? isForMainFrame, required bool ready}) =>
    !ready && isForMainFrame != false;

/// The full page URL: the server-minted frame URL (which already carries the
/// signed APP grant and `mode=app`) plus the render-time parameters. There is
/// no `origin` — an app has none, and the page proves that instead.
String buildMapFrameSrc(
  String frameUrl, {
  required MapLatLng center,
  required int zoom,
  required bool hasPin,
  String? theme,
  String? primaryColor,
}) {
  final url = Uri.parse(frameUrl);
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'lat': '${center.lat}',
    'lng': '${center.lng}',
    'zoom': '${hasPin ? 16 : zoom}',
    if (theme != null) 'theme': theme,
    if (primaryColor != null) 'primary': primaryColor,
  }).toString();
}

sealed class MapFrameMessage {
  const MapFrameMessage();
}

class MapFrameReady extends MapFrameMessage {
  const MapFrameReady();
}

class MapFrameFailed extends MapFrameMessage {
  const MapFrameFailed();
}

class MapFramePin extends MapFrameMessage {
  final MapLatLng pin;
  const MapFramePin(this.pin);
}

/// Validate-and-drop: anything not shaped exactly like a frame message is
/// null, including a pin with impossible coordinates.
MapFrameMessage? parseMapFrameMessage(String data) {
  Object? decoded;
  try {
    decoded = jsonDecode(data);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['source'] != kMapFrameSource) return null;
  switch (decoded['type']) {
    case 'ready':
      return const MapFrameReady();
    case 'failed':
      return const MapFrameFailed();
    case 'pin':
      final lat = decoded['lat'];
      final lng = decoded['lng'];
      if (lat is! num || lng is! num || !lat.isFinite || !lng.isFinite) {
        return null;
      }
      if (lat.abs() > 90 || lng.abs() > 180) return null;
      return MapFramePin(MapLatLng(lat.toDouble(), lng.toDouble()));
  }
  return null;
}

/// The recentre command as the script the WebView runs (Use my location,
/// restored progress).
String centerCommandScript(MapLatLng pin) {
  final command = jsonEncode({
    'source': kMapParentSource,
    'type': 'center',
    'lat': pin.lat,
    'lng': pin.lng,
    'zoom': 16,
  });
  return 'window.__myazaMapCommand && '
      'window.__myazaMapCommand(${jsonEncode(command)}); true;';
}

bool samePin(MapLatLng? a, MapLatLng b) =>
    a != null && (a.lat - b.lat).abs() < 1e-7 && (a.lng - b.lng).abs() < 1e-7;
