import 'dart:math' as math;
import 'dart:ui' show Size;

// ─── Web Mercator math for the dependency-free map pin picker ────────────────
//
// Pure and unit-tested — the picker widget is a thin gesture shell over these.
//
// Deliberately NOT google_maps_flutter / flutter_map: that means a native
// module or a tile-layer dependency (and a Google Maps API key per org) for
// what the picker needs — pan, zoom, one pin. The standard slippy-map maths
// below is ~60 lines, fully testable, and the tiles are plain Image.network.
//
// A MIRROR of the web SDK's lib/map-tiles.ts and the RN SDK's
// src/lib/map-tiles.ts — keep the three in lockstep.

const int kTileSize = 256;
const int kMinZoom = 3;
const int kMaxZoom = 19;

// Web Mercator's poles — beyond this the projection diverges.
const double _kMaxLat = 85.05112878;

class MapLatLng {
  final double lat;
  final double lng;
  const MapLatLng(this.lat, this.lng);
}

double clampLat(double lat) => lat.clamp(-_kMaxLat, _kMaxLat).toDouble();

double _wrapLng(double lng) {
  var l = lng;
  while (l > 180) {
    l -= 360;
  }
  while (l < -180) {
    l += 360;
  }
  return l;
}

/// World size in pixels at a zoom level.
double worldSize(int zoom) => (kTileSize * math.pow(2, zoom)).toDouble();

/// Project a coordinate to world pixels at a zoom level.
({double x, double y}) latLngToWorld(MapLatLng point, int zoom) {
  final size = worldSize(zoom);
  final lat = clampLat(point.lat);
  final sin = math.sin(lat * math.pi / 180);
  // Clamped into the world: at the pole cap the log term lands a float
  // epsilon outside [0, size], which would render as a phantom tile row.
  final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * size;
  return (
    x: (_wrapLng(point.lng) + 180) / 360 * size,
    y: y.clamp(0, size).toDouble(),
  );
}

/// Unproject world pixels back to a coordinate.
MapLatLng worldToLatLng(double x, double y, int zoom) {
  final size = worldSize(zoom);
  final n = math.pi - 2 * math.pi * y / size;
  return MapLatLng(
    180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))),
    _wrapLng(x / size * 360 - 180),
  );
}

class TilePlacement {
  final String key;
  final String url;

  /// Position relative to the viewport's top-left corner.
  final double left;
  final double top;
  const TilePlacement({
    required this.key,
    required this.url,
    required this.left,
    required this.top,
  });
}

/// The OSM tiles covering a viewport centred on [center]. Tiles outside the
/// world (above/below the poles) are skipped; longitude wraps.
List<TilePlacement> visibleTiles(
  MapLatLng center,
  int zoom,
  double width,
  double height,
) {
  final world = latLngToWorld(center, zoom);
  final tiles = <TilePlacement>[];
  final tileCount = math.pow(2, zoom).toInt();
  final originX = world.x - width / 2;
  final originY = world.y - height / 2;
  final firstX = (originX / kTileSize).floor();
  final firstY = (originY / kTileSize).floor();
  final lastX = ((originX + width) / kTileSize).floor();
  final lastY = ((originY + height) / kTileSize).floor();
  for (var ty = firstY; ty <= lastY; ty += 1) {
    if (ty < 0 || ty >= tileCount) continue;
    for (var tx = firstX; tx <= lastX; tx += 1) {
      final wrappedX = ((tx % tileCount) + tileCount) % tileCount;
      tiles.add(TilePlacement(
        key: '$zoom/$tx/$ty',
        url: 'https://tile.openstreetmap.org/$zoom/$wrappedX/$ty.png',
        left: tx * kTileSize - originX,
        top: ty * kTileSize - originY,
      ));
    }
  }
  return tiles;
}

/// The centre after a drag of (dx, dy) viewport pixels.
MapLatLng panCenter(MapLatLng center, int zoom, double dx, double dy) {
  final world = latLngToWorld(center, zoom);
  final next = worldToLatLng(world.x - dx, world.y - dy, zoom);
  return MapLatLng(clampLat(next.lat), next.lng);
}

/// Sensible starting views: gov-DB countries at country zoom, else a world view.
const Map<String, MapLatLng> _kCountryCenters = {
  'NG': MapLatLng(9.06, 8.68),
  'GH': MapLatLng(7.95, -1.02),
  'KE': MapLatLng(0.02, 37.9),
  'ZA': MapLatLng(-28.48, 24.68),
  'CI': MapLatLng(7.54, -5.55),
};

({MapLatLng center, int zoom}) defaultMapView(String? country) {
  final center =
      country == null ? null : _kCountryCenters[country.toUpperCase()];
  return center != null
      ? (center: center, zoom: 6)
      : (center: const MapLatLng(6.5, 12), zoom: 3);
}

// ─── The map surface's height on the pin step ────────────────────────────────
//
// A phone gets 40% of its height, clamped to 240–360: on a phone the map owns
// every touch, so the taller it is the less page is left to scroll on, and
// Continue has to stay reachable. From a tablet-class width (the web SDK's
// `sm` breakpoint) it is a flat 420. Mirrors the web SDK's
// `h-[40vh] min-h-[240px] max-h-[360px] sm:h-[420px]` and the RN
// `mapSurfaceHeight`; keep the three in lockstep.

const double kMapSurfacePhoneFraction = 0.4;
const double kMapSurfacePhoneMin = 240;
const double kMapSurfacePhoneMax = 360;
const double kMapSurfaceWideBreakpoint = 640;
const double kMapSurfaceWide = 420;

double mapSurfaceHeight(Size viewport) {
  if (viewport.width >= kMapSurfaceWideBreakpoint) return kMapSurfaceWide;
  final fraction = (viewport.height * kMapSurfacePhoneFraction).roundToDouble();
  return fraction.clamp(kMapSurfacePhoneMin, kMapSurfacePhoneMax).toDouble();
}
