import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_picker.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_picker_parts.dart';

// ─── The map's zoom, which is easy to get quietly wrong ──────────────────────
//
// The picker commits its OWN pans through onChange, so the parent hands the
// new pin straight back as a prop. Comparing the incoming value against the
// old PROP therefore reads every drag as an external recentre — which zooms
// the map in, including on someone who had deliberately zoomed out to find
// their area. Nothing errors; the map just fights the applicant.

/// Zoom is private state, so it is read the way the map itself uses it: the
/// tile keys carry it.
int _zoomOf(WidgetTester tester) {
  final layer = tester.widget<MapTileLayer>(find.byType(MapTileLayer));
  return int.parse(layer.tiles.first.key.split('/').first);
}

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: child),
    );

void main() {
  const lagos = MapLatLng(6.4281, 3.4219);

  testWidgets('a pin step opens close enough to read a building',
      (tester) async {
    await tester.pumpWidget(_host(MapPinPicker(
      value: lagos,
      onChange: (_) {},
      defaultCenter: lagos,
      defaultZoom: 6,
    )));
    expect(_zoomOf(tester), kMapPinZoom);
  });

  testWidgets('a summary map keeps the zoom its caller asked for',
      (tester) async {
    // The close-in zoom exists to answer "is the pin on your building?", and
    // a read-only confirmation never asks that.
    await tester.pumpWidget(_host(MapPinPicker(
      value: lagos,
      onChange: (_) {},
      defaultCenter: lagos,
      defaultZoom: 16,
      interactive: false,
    )));
    expect(_zoomOf(tester), 16);
  });

  testWidgets('the applicant\'s own zoom survives their next pan',
      (tester) async {
    var pin = lagos;
    late StateSetter setOuter;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return MapPinPicker(
          value: pin,
          onChange: (next) => setOuter(() => pin = next),
          defaultCenter: lagos,
          defaultZoom: 6,
        );
      },
    )));
    expect(_zoomOf(tester), kMapPinZoom);

    // Zoom out to look around, the way someone hunting for their area does.
    await tester.tap(find.bySemanticsLabel('Zoom out'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Zoom out'));
    await tester.pump();
    expect(_zoomOf(tester), kMapPinZoom - 2);

    // Now pan. The parent hands the committed pin straight back as a prop,
    // which must NOT read as an external recentre.
    await tester.drag(find.byType(MapPinPicker), const Offset(-90, -60));
    await tester.pumpAndSettle();
    expect(_zoomOf(tester), kMapPinZoom - 2);
  });

  testWidgets('an external recentre does zoom back in', (tester) async {
    await tester.pumpWidget(_host(MapPinPicker(
      value: lagos,
      onChange: (_) {},
      defaultCenter: lagos,
      defaultZoom: 6,
    )));
    await tester.tap(find.bySemanticsLabel('Zoom out'));
    await tester.pump();
    expect(_zoomOf(tester), kMapPinZoom - 1);

    // A search pick or a locate: somewhere else entirely.
    await tester.pumpWidget(_host(MapPinPicker(
      value: const MapLatLng(4.9324, 8.3254),
      onChange: (_) {},
      defaultCenter: lagos,
      defaultZoom: 6,
    )));
    await tester.pump();
    expect(_zoomOf(tester), kMapPinZoom);
  });

  testWidgets('the OSM attribution is always visible', (tester) async {
    // Required by the tile-usage terms, on the read-only map too.
    for (final interactive in [true, false]) {
      await tester.pumpWidget(_host(MapPinPicker(
        value: lagos,
        onChange: (_) {},
        defaultCenter: lagos,
        defaultZoom: 16,
        interactive: interactive,
      )));
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    }
  });
}
