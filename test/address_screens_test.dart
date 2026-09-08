import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_detail_fields.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_location_row.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_photo_dropzone.dart';
import 'package:myaza_kyc_sdk_flutter/src/screens/address/address_search_results.dart';

// ─── The address flow's capture screens ─────────────────────────────────────
//
// Copy and state, pinned. The wording is a CROSS-SDK MIRROR of the web SDK, so
// a change here that is not made in the other two leaves one platform telling
// an applicant something the others do not. The presence primer, disclosures
// and success card live in address_presence_screens_test.dart (200-line rule).

/// The test surface is 800x600 whatever a SizedBox says, so the host scrolls
/// rather than pretending to be a tall phone: anything below the fold is
/// reached with `ensureVisible`, the way a person reaches it by scrolling.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('the current-location row', () {
    testWidgets('shows where it will take them once a fix lands',
        (tester) async {
      await tester.pumpWidget(_host(CurrentLocationRow(
        hint: '11 Bassey Street, Calabar',
        locating: false,
        onTap: () {},
      )));
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.text('11 Bassey Street, Calabar'), findsOneWidget);
    });

    testWidgets('says it is looking, then what it offers', (tester) async {
      await tester.pumpWidget(_host(
          CurrentLocationRow(hint: null, locating: true, onTap: () {})));
      expect(find.text('Finding your location…'), findsOneWidget);

      await tester.pumpWidget(_host(
          CurrentLocationRow(hint: null, locating: false, onTap: () {})));
      expect(find.text('Lands the pin right where you are'), findsOneWidget);
    });
  });

  group('the search results', () {
    testWidgets('each backend names its own way out', (tester) async {
      await tester.pumpWidget(_host(const AddressSearchResults(
        rows: [],
        emptyMessage: 'No matches. Use your location or place the pin by hand.',
      )));
      expect(
          find.text(
              'No matches. Use your location or place the pin by hand.'),
          findsOneWidget);

      await tester.pumpWidget(_host(const AddressSearchResults(
        rows: [],
        emptyMessage: 'No matches. Drag the map to place the pin instead.',
      )));
      expect(find.text('No matches. Drag the map to place the pin instead.'),
          findsOneWidget);
    });
  });

  group('the edit-details primitives', () {
    testWidgets('the country row is a read-only fact, named not coded',
        (tester) async {
      await tester
          .pumpWidget(_host(const AddressCountryRow(country: 'NG')));
      expect(find.text('Country'), findsOneWidget);
      expect(find.text('Nigeria'), findsOneWidget);
      // No country, no row — never an empty frame.
      await tester
          .pumpWidget(_host(const AddressCountryRow(country: null)));
      expect(find.text('Country'), findsNothing);
    });

    testWidgets('a section heading reads as the group label', (tester) async {
      await tester
          .pumpWidget(_host(const AddressSectionHeading('Area and region')));
      expect(find.text('AREA AND REGION'), findsOneWidget);
    });
  });

  group('the entrance photo', () {
    testWidgets('offers the capture, and says it is optional', (tester) async {
      await tester.pumpWidget(_host(AddressPhotoDropzone(
        required: false,
        uploaded: false,
        uploading: false,
        previewPath: null,
        onPick: () {},
        onRemove: () {},
      )));
      expect(find.text('Take or upload a photo'), findsOneWidget);
      expect(
          find.text(
              'The gate, front door or the building itself. Optional.'),
          findsOneWidget);
      expect(find.text('JPEG · PNG · WebP'), findsOneWidget);
    });

    testWidgets('drops the optional note when the workflow requires one',
        (tester) async {
      await tester.pumpWidget(_host(AddressPhotoDropzone(
        required: true,
        uploaded: false,
        uploading: false,
        previewPath: null,
        onPick: () {},
        onRemove: () {},
      )));
      expect(find.text('The gate, front door or the building itself.'),
          findsOneWidget);
    });

    testWidgets('a restored session states the photo rather than faking it',
        (tester) async {
      // The mediaId survived the resume; the bytes did not, so a broken image
      // would be worse than saying so.
      await tester.pumpWidget(_host(AddressPhotoDropzone(
        required: false,
        uploaded: true,
        uploading: false,
        previewPath: null,
        onPick: () {},
        onRemove: () {},
      )));
      expect(find.text('Entrance photo added'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });
  });
}
