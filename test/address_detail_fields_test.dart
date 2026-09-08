import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/address_field_modes.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_area_fields.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_detail_fields.dart';

// ─── The edit-details fields honour their workflow modes ─────────────────────
//
// A required field wears its mark, an off field is not rendered, and the
// area section disappears whole when nothing in it is offered. The rule
// itself is pinned by address_field_modes_test.dart (shared vectors); this
// is the widget half.

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

TextEditingController _controller(WidgetTester tester) {
  final c = TextEditingController();
  addTearDown(c.dispose);
  return c;
}

Map<String, AddressFieldMode> _modes(Map<String, AddressFieldMode> over) => {
      for (final key in kAddressFieldKeys) key: over[key] ?? AddressFieldMode.optional,
    };

void main() {
  group('AddressEditField', () {
    testWidgets('marks a required field with an asterisk in the error colour',
        (tester) async {
      await tester.pumpWidget(_host(AddressEditField(
        label: 'City',
        maxLength: 80,
        required: true,
        controller: _controller(tester),
        onChanged: (_) {},
      )));
      final label = tester.widget<Text>(find.text('City *'));
      final span = label.textSpan! as TextSpan;
      expect(span.text, 'City');
      final mark = span.children!.single as TextSpan;
      expect(mark.text, ' *');
      expect(mark.style?.color, MyazaColors.error);
    });

    testWidgets('an optional field carries no mark', (tester) async {
      await tester.pumpWidget(_host(AddressEditField(
        label: 'City',
        maxLength: 80,
        controller: _controller(tester),
        onChanged: (_) {},
      )));
      expect(find.text('City'), findsOneWidget);
      expect(find.text('City *'), findsNothing);
    });
  });

  group('AddressAreaFields', () {
    testWidgets('renders nothing when every area field is off', (tester) async {
      await tester.pumpWidget(_host(AddressAreaFields(
        modes: _modes({
          'neighbourhood': AddressFieldMode.off,
          'city': AddressFieldMode.off,
          'state': AddressFieldMode.off,
          'postcode': AddressFieldMode.off,
        }),
        neighbourhood: _controller(tester),
        city: _controller(tester),
        state: _controller(tester),
        postcode: _controller(tester),
        country: 'NG',
        onChanged: (_) {},
      )));
      expect(find.byType(AddressEditField), findsNothing);
      expect(find.text('AREA AND REGION'), findsNothing);
      expect(find.text('Country'), findsNothing);
    });

    testWidgets('hides only the fields that are off and marks the required ones',
        (tester) async {
      await tester.pumpWidget(_host(AddressAreaFields(
        modes: _modes({
          'city': AddressFieldMode.required,
          'state': AddressFieldMode.off,
        }),
        neighbourhood: _controller(tester),
        city: _controller(tester),
        state: _controller(tester),
        postcode: _controller(tester),
        country: 'NG',
        onChanged: (_) {},
      )));
      expect(find.text('AREA AND REGION'), findsOneWidget);
      expect(find.text('Neighbourhood'), findsOneWidget);
      expect(find.text('City *'), findsOneWidget);
      expect(find.text('State'), findsNothing);
      expect(find.text('Area code'), findsOneWidget);
      expect(find.text('Country'), findsOneWidget);
    });
  });
}
