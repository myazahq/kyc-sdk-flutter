import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/map_pin_picker.dart';

// A squared-off picker (the review card clips it) draws no border and no
// radius of its own: its rounded bottom corners and hairline sat where the map
// met the address band (user report 2026-09-08). Mirrors RN's cornerRadius.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: const [MyazaColorScheme.light]),
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  BoxDecoration decorationOf(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    return containers
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null || d.borderRadius == BorderRadius.zero);
  }

  testWidgets('the default picker keeps its border and radius', (tester) async {
    await tester.pumpWidget(host(MapPinPicker(
      value: const MapLatLng(4.97, 8.34),
      onChange: (_) {},
      defaultCenter: const MapLatLng(4.97, 8.34),
      defaultZoom: 16,
      interactive: false,
    )));
    final d = decorationOf(tester);
    expect(d.border, isNotNull);
    expect(d.borderRadius, BorderRadius.circular(MyazaRadius.md));
  });

  testWidgets('cornerRadius 0 drops the border and squares the corners', (tester) async {
    await tester.pumpWidget(host(MapPinPicker(
      value: const MapLatLng(4.97, 8.34),
      onChange: (_) {},
      defaultCenter: const MapLatLng(4.97, 8.34),
      defaultZoom: 16,
      interactive: false,
      cornerRadius: 0,
    )));
    final d = decorationOf(tester);
    expect(d.border, isNull);
    expect(d.borderRadius, BorderRadius.zero);
  });
}
