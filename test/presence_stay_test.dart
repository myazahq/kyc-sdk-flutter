import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/presence/presence_stay.dart';

void main() {
  test('no stay open is null', () {
    expect(parsePresenceStay(null), isNull);
    expect(parsePresenceStay(const {}), isNull);
  });

  test('reads the arrival and the next report time', () {
    final stay = parsePresenceStay(const {'since': 1000, 'nextReportAt': 2101000});
    expect(stay?.since, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(stay?.nextReportAt, DateTime.fromMillisecondsSinceEpoch(2101000));
  });

  test('a half answer is no answer', () {
    expect(parsePresenceStay(const {'since': 1000}), isNull);
    expect(parsePresenceStay(const {'since': 1000, 'nextReportAt': 'soon'}), isNull);
  });
}
