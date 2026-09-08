import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/regions.dart';

// ─── The geo row ──────────────────────────────────────────────────────────────
//
// The visitor's IP country is lifted to the top of a picker and tagged, so a
// guess made on their behalf is one tap away rather than buried among two
// hundred rows. ONE rule serves the country-select step (bare codes) and the
// dial-code sheet (entry records); the web and RN SDKs carry the same
// semantics, and this pins them here.

void main() {
  const codes = ['NG', 'GH', 'FR', 'US'];
  String same(String c) => c;

  test('lifts the geo country out and drops it from the rest', () {
    final split = pinGeoRow(codes, 'GH', same);
    expect(split.pinned, 'GH');
    expect(split.rest, ['NG', 'FR', 'US']);
  });

  test('is case-insensitive about the guess', () {
    expect(pinGeoRow(codes, ' gh ', same).pinned, 'GH');
  });

  test('pins nothing when there is no guess', () {
    expect(pinGeoRow(codes, null, same).pinned, isNull);
    expect(pinGeoRow(codes, null, same).rest, codes);
    expect(pinGeoRow(codes, '', same).pinned, isNull);
  });

  test('stays subject to the search: an excluded guess is not resurrected', () {
    // `visible` is the already-filtered list; typing "fr" left GH out of it.
    final split = pinGeoRow(const ['FR'], 'GH', same);
    expect(split.pinned, isNull);
    expect(split.rest, ['FR']);
  });

  test('works over records, returning the same entry', () {
    final entries = [
      (iso: 'NG', name: 'Nigeria', dial: '234'),
      (iso: 'GH', name: 'Ghana', dial: '233'),
    ];
    final split = pinGeoRow(entries, 'GH', (e) => e.iso);
    expect(split.pinned, entries[1]);
    expect(split.rest, [entries[0]]);
  });
}
