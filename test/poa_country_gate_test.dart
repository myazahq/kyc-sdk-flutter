import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/poa_country_gate.dart';

// The Proof of Address step's Continue holds until the address scope's country
// is declared (user decision 2026-09-08). Mirrored on web and RN.
void main() {
  test('outside the address scope the flow country stands', () {
    expect(poaCountryDeclared(scope: null, selectedCountry: null, offered: const []), isTrue);
    expect(poaCountryDeclared(scope: 'contact', selectedCountry: null, offered: const []), isTrue);
  });

  test('on the address scope a picked country declares it', () {
    expect(poaCountryDeclared(scope: 'address', selectedCountry: 'NG', offered: const ['NG', 'GH']), isTrue);
    expect(poaCountryDeclared(scope: 'address', selectedCountry: null, offered: const ['NG', 'GH']), isFalse);
    expect(poaCountryDeclared(scope: 'address', selectedCountry: ' ', offered: const ['NG', 'GH']), isFalse);
  });

  test('one accepted country is a settled fact, not a choice', () {
    expect(poaCountryDeclared(scope: 'address', selectedCountry: null, offered: const ['NG']), isTrue);
  });

  test('the PoA screen gates Continue on it', () {
    final src = File('lib/src/screens/proof_of_address_screen.dart').readAsStringSync();
    expect(src, contains('poaCountryDeclared('));
    // The gate sits on the button, not merely computed.
    expect(src, matches(RegExp(r"label: 'Continue',[\s\S]{0,200}countryDeclared")));
  });
}
