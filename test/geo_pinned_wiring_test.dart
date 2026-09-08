import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Every picker offers the geo row ─────────────────────────────────────────
//
// The pin only helps where the screen actually hands the picker the IP
// country. Nothing at runtime says when a caller forgets, so this reads the
// wiring: the country-select step, the phone field on both of its mounts
// (contact verification, the KYB company profile). Mirrors the RN scan.

String read(String rel) => File('lib/src/$rel').readAsStringSync();

void main() {
  test('the country-select step hands the picker the IP country', () {
    expect(read('screens/country_select_screen.dart'),
        contains('geoCountry: state.serverConfig.geoCountry'));
    expect(read('widgets/country_region_picker.dart'),
        contains("badge: 'Your location'"));
  });

  test('the phone field pins it in the dial-code sheet, on both mounts', () {
    expect(read('widgets/phone_number_input.dart'),
        contains('pinned: widget.geoCountry'));
    expect(read('widgets/dial_code_picker.dart'), contains("'Your location'"));
    expect(read('screens/contact_verification_screen.dart'),
        contains('geoCountry: settings.geoCountry'));
    expect(read('screens/contact_verification_parts.dart'),
        contains('geoCountry: geoCountry'));
    expect(read('screens/business_details_screen.dart'),
        contains('geoCountry: s.serverConfig.geoCountry'));
    expect(read('screens/business_company_info_fields.dart'),
        contains('geoCountry: geoCountry'));
  });

  test('the address-scope country control pins it on top of a grouped sheet',
      () {
    // The sheet, not a line under the field: "Your location looks like X. Use
    // it" was removed (user decision 2026-09-06) in favour of the same pinned
    // row the country-select step and the phone field carry.
    final control = read('widgets/address_country_control.dart');
    expect(control,
        contains('geoCountry: inferredCountry(state.serverConfig.geoCountry)'));
    expect(control, contains('grouped: true'));
    expect(control, isNot(contains('looks like')));
    final field = read('widgets/country_field.dart');
    expect(field, contains('pinned: geoCountry'));
    expect(field, contains('grouped: grouped'));
  });
}
