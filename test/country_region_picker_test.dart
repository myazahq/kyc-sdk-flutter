import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/country_option_tile.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/country_region_picker.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/geo_badge.dart';

// ─── The picker pins the visitor's country ───────────────────────────────────
//
// The IP-derived country sits at the very top, tagged, and nowhere else: a row
// that appeared twice would read as two countries. It is still subject to the
// search, so a query that excludes it drops the pin rather than keeping a row
// that does not match. Mirrors the web SDK's CountryRegionPicker.

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 600, child: child)),
    );

List<String> tileCodes(WidgetTester tester) =>
    tester.widgetList<CountryOptionTile>(find.byType(CountryOptionTile))
        .map((t) => t.code)
        .toList();

void main() {
  const codes = ['NG', 'GH', 'FR', 'US', 'KE', 'BR'];

  testWidgets('the geo country is first, tagged, and not repeated in its region',
      (tester) async {
    await tester.pumpWidget(host(CountryRegionPicker(
      codes: codes,
      selected: null,
      geoCountry: 'gh',
      onSelect: (_) {},
    )));
    await tester.pump();

    final tiles = tileCodes(tester);
    expect(tiles.first, 'GH');
    expect(tiles.where((c) => c == 'GH').length, 1);
    expect(find.widgetWithText(GeoBadge, 'Your location'), findsOneWidget);
    // Africa still lists the other two, alphabetically.
    expect(tiles.sublist(1, 3), ['KE', 'NG']);
  });

  testWidgets('a search that excludes the geo country drops the pin',
      (tester) async {
    await tester.pumpWidget(host(CountryRegionPicker(
      codes: codes,
      selected: null,
      geoCountry: 'GH',
      onSelect: (_) {},
    )));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'fr');
    await tester.pump();

    expect(tileCodes(tester), ['FR']);
    expect(find.byType(GeoBadge), findsNothing);
  });

  testWidgets('a guess the workflow does not offer pins nothing', (tester) async {
    await tester.pumpWidget(host(CountryRegionPicker(
      codes: codes,
      selected: null,
      geoCountry: 'JP',
      onSelect: (_) {},
    )));
    await tester.pump();

    expect(find.byType(GeoBadge), findsNothing);
    expect(tileCodes(tester).first, 'GH');
  });

  testWidgets('tapping the pinned row picks that country', (tester) async {
    String? picked;
    await tester.pumpWidget(host(CountryRegionPicker(
      codes: codes,
      selected: null,
      geoCountry: 'GH',
      onSelect: (c) => picked = c,
    )));
    await tester.pump();
    await tester.tap(find.byType(CountryOptionTile).first);
    expect(picked, 'GH');
  });
}
