import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Autocomplete ranks like a ride-hailing app ──────────────────────────────
//
// The device fix rides the autocomplete call as `lat`/`lng`, a RANKING bias so
// nearby streets come first: without it "Awolowo Road" in Calabar ranks
// against every Awolowo Road in the country. KYCApiService builds its own Dio
// with no seam to stub, so this reads the wiring: the call names the params,
// the search body carries the fix, and the search step passes the flow's fix.
// Mirrors the web and RN SDKs' addressAutocomplete.

String read(String rel) => File('lib/src/$rel').readAsStringSync();

void main() {
  test('the call sends the fix as lat/lng only when one exists', () {
    final source = read('services/api_address_calls.dart');
    expect(source, contains('MapLatLng? near'));
    expect(
      source,
      contains(
          "if (near != null) ...{'lat': '\${near.lat}', 'lng': '\${near.lng}'}"),
    );
  });

  test('the search body and step pass the current fix through', () {
    expect(read('screens/address/address_search_body.dart'),
        contains('near: widget.near'));
    expect(read('screens/address/address_search_step.dart'),
        contains('MapLatLng(flow.fix!.lat, flow.fix!.lng)'));
  });
}
