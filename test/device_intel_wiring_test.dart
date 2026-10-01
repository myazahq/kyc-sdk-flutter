import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── The provider wires the device-intel gate, not a copy of it ──────────────
//
// fingerprint_payload.dart owns the Device Intelligence decision for both the
// submission and the upload header. These pin that the flow actually calls it
// with the workflow's flag, since an omitted argument compiles and passes.

void main() {
  final provider =
      File('lib/src/providers/kyc_provider.dart').readAsStringSync();

  test('the submission fingerprint goes through the gate', () {
    expect(provider, contains('await collectFingerprint('));
    expect(
        provider, contains('deviceIntelligence: _config.deviceIntelligence,'));
    expect(provider, contains('DeviceSignals.instance.collect('));
    expect(provider, contains('playIntegrityCloudProjectNumber'));
  });

  test('the API client reads the upload header from the gate', () {
    expect(provider, contains('deviceId: uploadDeviceIdSource('));
  });

  test('both config paths carry the Play Integrity project', () {
    final gate = File('lib/src/widgets/workflow_gate.dart').readAsStringSync();
    expect(
        gate,
        contains(
            'playIntegrityCloudProjectNumber: res.playIntegrityCloudProjectNumber'));
    expect(
        provider,
        contains(
            'playIntegrityCloudProjectNumber: response.playIntegrityCloudProjectNumber'));
  });
}
