import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_review_map.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_marker.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_picker.dart';

// The review card's map falls back in the SAME order as the web and RN cards:
// the picture, then the framed Google map the pin step drew, then the built-in
// tiles. The middle rung was missing, so a deployment without the Maps Static
// API confirmed the address on OpenStreetMap while RN confirmed it on Google
// (user report 2026-09-08).
//
// And a refused picture must take the SDK's overlay pin with it: the live maps
// draw their own, so keeping the overlay put two pins on the framed map (user
// report 2026-09-08, the iPhone).

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: child),
    );

void main() {
  ReviewMapSurface surface({
    bool stubbed = false,
    bool hasStatic = true,
    bool staticFailed = false,
    bool hasFrame = true,
  }) =>
      reviewMapSurface(
        vendorsStubbed: stubbed,
        hasStaticMap: hasStatic,
        staticMapFailed: staticFailed,
        hasFrame: hasFrame,
      );

  test('the picture leads whenever the deployment serves one', () {
    expect(surface(), ReviewMapSurface.picture);
    expect(surface(hasFrame: false), ReviewMapSurface.picture);
  });

  test('a refused picture falls back to the framed map before the built-in one', () {
    expect(surface(staticFailed: true), ReviewMapSurface.framed);
    expect(surface(hasStatic: false), ReviewMapSurface.framed);
    expect(surface(staticFailed: true, hasFrame: false), ReviewMapSurface.builtIn);
  });

  test('SANDBOX shows the stand-in whatever else is on offer', () {
    expect(surface(stubbed: true), ReviewMapSurface.stub);
    expect(surface(stubbed: true, hasStatic: false, hasFrame: false), ReviewMapSurface.stub);
  });

  testWidgets('a refused picture hands over to the live map with ONE pin', (tester) async {
    const calabar = MapLatLng(4.9320, 8.3259);
    // The test binding answers every network image with a 400, so the picture
    // is refused the moment it is asked for.
    await tester.pumpWidget(_host(const AddressReviewMap(
      pin: calabar,
      vendorsStubbed: false,
      mapsFrameUrl: null,
      staticMapUrl: 'https://example.test/static-map',
      imageHeaders: {},
    )));
    // While the bytes are still awaited the picture's overlay pin is the only
    // one, and no live map is mounted under it.
    expect(find.byType(MapPinMarker), findsOneWidget);
    expect(find.byType(MapPinPicker), findsNothing);

    await tester.pumpAndSettle();
    // The live map now draws, and it carries the only pin: the overlay went
    // with the picture rather than stacking a second pin on the map's own.
    expect(find.byType(MapPinPicker), findsOneWidget);
    expect(find.byType(MapPinMarker), findsOneWidget);
  });
}
