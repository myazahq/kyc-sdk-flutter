import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/dial_code_rows.dart';

// The country sheet's list as data: the pinned geo row and the region
// grouping the address-scope country control asks for. The RN SDK's
// dialCodeRows.test.ts pins the same rules.

const List<DialCodeEntry> entries = [
  (iso: 'FR', name: 'France', dial: '33'),
  (iso: 'GH', name: 'Ghana', dial: '233'),
  (iso: 'NG', name: 'Nigeria', dial: '234'),
  (iso: 'US', name: 'United States', dial: '1'),
];

List<String> codes(List<DialCodeItem> items) => [
      for (final item in items)
        switch (item) {
          DialCodeHeaderItem(:final region) => '#$region',
          DialCodeRowItem(:final entry) => entry.iso,
        },
    ];

void main() {
  test('flat: the geo row first, then the rest in the given order', () {
    final items = buildDialCodeItems(entries, 'ng', grouped: false);
    expect(codes(items), ['NG', 'FR', 'GH', 'US']);
    expect((items.first as DialCodeRowItem).pinned, isTrue);
    expect((items[1] as DialCodeRowItem).pinned, isFalse);
  });

  test('grouped: the geo row first, then region headers A to Z within', () {
    final items = buildDialCodeItems(entries, 'GH', grouped: true);
    expect(codes(items),
        ['GH', '#Africa', 'NG', '#Europe', 'FR', '#Americas', 'US']);
  });

  test('grouped without a guess opens straight on the first region', () {
    final items = buildDialCodeItems(entries, null, grouped: true);
    expect(codes(items).first, '#Africa');
    expect(items.whereType<DialCodeRowItem>().any((i) => i.pinned), isFalse);
  });

  test("keeps the caller's entries, dial codes included", () {
    final items = buildDialCodeItems(entries, null, grouped: true);
    final ng = items
        .whereType<DialCodeRowItem>()
        .firstWhere((i) => i.entry.iso == 'NG');
    expect(ng.entry.dial, '234');
  });

  test('a guess the filter excluded is not resurrected', () {
    final items = buildDialCodeItems([entries.first], 'GH', grouped: true);
    expect(codes(items), ['#Europe', 'FR']);
  });
}
