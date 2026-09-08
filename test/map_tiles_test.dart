import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';

// Web Mercator math for the address-collection map picker. A port of the web
// and RN SDKs' mapTiles tests — the three implementations must agree, because
// a pin placed on one platform is read back on the others.

void main() {
  group('web mercator projection', () {
    test('puts the origin at the world centre', () {
      final world = latLngToWorld(const MapLatLng(0, 0), 1);
      expect(world.x, closeTo(worldSize(1) / 2, 1e-6));
      expect(world.y, closeTo(worldSize(1) / 2, 1e-6));
    });

    test('round-trips a Lagos coordinate', () {
      const point = MapLatLng(6.4281, 3.4219);
      final world = latLngToWorld(point, 17);
      final back = worldToLatLng(world.x, world.y, 17);
      expect(back.lat, closeTo(point.lat, 1e-5));
      expect(back.lng, closeTo(point.lng, 1e-5));
    });

    test('clamps latitudes beyond the projection poles', () {
      final world = latLngToWorld(const MapLatLng(89, 0), 3);
      expect(world.y, greaterThanOrEqualTo(0));
    });
  });

  group('visibleTiles', () {
    test('covers a viewport with contiguous tiles and wraps longitude', () {
      final tiles = visibleTiles(const MapLatLng(6.4281, 179.9), 5, 512, 256);
      expect(tiles.length, greaterThanOrEqualTo(6));
      final pattern =
          RegExp(r'^https://tile\.openstreetmap\.org/5/\d+/\d+\.png$');
      for (final tile in tiles) {
        expect(tile.url, matches(pattern));
      }
    });

    test('skips rows above the world', () {
      final tiles = visibleTiles(const MapLatLng(85, 0), 3, 256, 2048);
      for (final tile in tiles) {
        final y = int.parse(
            tile.url.split('/').last.replaceFirst('.png', ''));
        expect(y, greaterThanOrEqualTo(0));
        expect(y, lessThan(8));
      }
    });
  });

  group('panCenter', () {
    test('dragging the map east moves the centre west', () {
      const start = MapLatLng(6.4281, 3.4219);
      final next = panCenter(start, 12, 100, 0);
      expect(next.lng, lessThan(start.lng));
      expect(next.lat, closeTo(start.lat, 1e-3));
    });
  });

  group('defaultMapView', () {
    test('opens gov-DB countries at country zoom and unknowns wide', () {
      final ng = defaultMapView('NG');
      expect(ng.zoom, 6);
      expect(ng.center.lat, closeTo(9.06, 1e-6));

      final unknown = defaultMapView('FR');
      expect(unknown.zoom, 3);

      final none = defaultMapView(null);
      expect(none.zoom, 3);
    });
  });
}
