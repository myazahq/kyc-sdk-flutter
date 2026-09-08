import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';

// A workflow mount skips /config, so every capability fact the /config path
// carries has to ride the workflow resolution AND be forwarded by the gate.
// Both halves went missing for the address facts (search step, framed map,
// Street View, geo default all silently off on workflow embeds, user report
// 2026-09-08); this pins them as a source diff so the next field cannot slip.

/// `key: response.key` pairs in kyc_provider's /config → ServerSdkConfig block
/// (built as `final ready = ServerSdkConfig(...)` so the opening-step nudge can
/// read it before it is applied).
Set<String> _configForwardedKeys() {
  final src = File('lib/src/providers/kyc_provider.dart').readAsStringSync();
  final block = RegExp(r'final ready = ServerSdkConfig\(\s*status: ServerConfigStatus\.ready,(.*?)\);', dotAll: true)
      .firstMatch(src)!
      .group(1)!;
  return RegExp(r'(\w+): response\.\1').allMatches(block).map((m) => m.group(1)!).toSet();
}

/// `key: res.key` pairs in the workflow gate's ServerSdkConfig block.
Set<String> _gateForwardedKeys() {
  final src = File('lib/src/widgets/workflow_gate.dart').readAsStringSync();
  final block = RegExp(r'serverConfig: ServerSdkConfig\(\s*status: ServerConfigStatus\.ready,(.*?)\),', dotAll: true)
      .firstMatch(src)!
      .group(1)!;
  return RegExp(r'(\w+): res\.\1').allMatches(block).map((m) => m.group(1)!).toSet();
}

void main() {
  test('the workflow gate forwards every server fact the /config path forwards', () {
    final fromConfig = _configForwardedKeys();
    expect(fromConfig, containsAll(['idTypes', 'branding', 'geoCountry', 'addressSearch', 'addressSearchMode', 'mapsFrameUrl']));
    expect(_gateForwardedKeys(), containsAll(fromConfig));
  });

  test('WorkflowResolution parses the address capability facts /config serves', () {
    final res = WorkflowResolution.fromJson({
      'workflow': {'id': 'wf_1', 'name': 'Demo', 'version': 3},
      'config': {'scope': 'address', 'country': 'NG'},
      'environment': 'DEVELOPMENT',
      'idTypes': <Map<String, dynamic>>[],
      'geoCountry': 'NG',
      'addressSearch': true,
      'addressSearchMode': 'autocomplete',
      'mapsFrameUrl': 'http://host/embed/map?grant=x&mode=app',
    });
    expect(res.geoCountry, 'NG');
    expect(res.addressSearch, isTrue);
    expect(res.addressSearchMode, 'autocomplete');
    expect(res.mapsFrameUrl, 'http://host/embed/map?grant=x&mode=app');
    // Absent facts read as the /config parser reads them: off, not null-crash.
    final bare = WorkflowResolution.fromJson({'config': <String, dynamic>{}});
    expect(bare.addressSearch, isFalse);
    expect(bare.mapsFrameUrl, isNull);
  });
}
