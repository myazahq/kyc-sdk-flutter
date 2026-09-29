import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/kyc_config.dart';

// The progress bar is the default indicator (2026-09-29). Steps and none stay
// available, and a value this build does not know takes the default.

void main() {
  test('a config that says nothing draws the bar', () {
    const config = MyazaKYCConfig(apiKey: 'pk_test_x');
    expect(config.progressStyle, MyazaProgressStyle.bar);
  });

  test('a workflow value maps to its style, and an unknown one to the bar', () {
    expect(MyazaProgressStyle.fromJson('steps'), MyazaProgressStyle.steps);
    expect(MyazaProgressStyle.fromJson('none'), MyazaProgressStyle.none);
    expect(MyazaProgressStyle.fromJson('bar'), MyazaProgressStyle.bar);
    expect(MyazaProgressStyle.fromJson('dots'), MyazaProgressStyle.bar);
  });
}
