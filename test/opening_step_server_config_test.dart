import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/myaza_kyc_sdk_flutter.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/kyc_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/step_order.dart';

// ─── The opening step reads the server's facts ───────────────────────────────
//
// Which steps EXIST depends on what the server serves: the address search
// step is in the order only when a search backend answers. An opening step
// computed off the loading placeholder put a consent-less address flow
// straight onto the pin step, with the search screen appearing in the order a
// moment later behind it (user report 2026-09-08). Every reader of the opening
// step now passes the config it holds, and the late /config path moves an
// applicant still standing on the placeholder's opening step to the real one.

MyazaKYCConfig _config({String? scope}) => MyazaKYCConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      consentStep: false,
      scope: scope,
      addressCollection:
          scope == 'address' ? const AddressCollectionConfig(enabled: true) : null,
    );

const _ready = ServerSdkConfig(status: ServerConfigStatus.ready, addressSearch: true);

void main() {
  test('opens a consent-less address flow on the search step once search exists', () {
    expect(openingStep(_config(scope: 'address'), serverConfig: _ready), KYCStep.addressSearch);
    // The placeholder alone still lands on the pin: nothing says search exists yet.
    expect(openingStep(_config(scope: 'address')), KYCStep.addressCollection);
  });

  test('facts that add no step change nothing', () {
    expect(openingStep(_config(), serverConfig: _ready), KYCStep.idType);
    expect(openingStep(_config()), KYCStep.idType);
  });

  test('every reader passes the server config it holds', () {
    final provider = File('lib/src/providers/kyc_provider.dart').readAsStringSync();
    final widget = File('lib/src/widgets/myaza_kyc_widget.dart').readAsStringSync();
    // The preloaded config is read BEFORE the opening step is computed.
    expect(
      provider.indexOf('ref.read(preloadedServerConfigProvider)'),
      lessThan(provider.indexOf('openingStep(_config, serverConfig: preloaded)')),
    );
    // The late /config path nudges an untouched applicant onto the real opening step.
    expect(provider, contains('currentStep: state.currentStep == before && after != before ? after : null'));
    expect(widget, contains('openingStep(config, serverConfig: state.serverConfig)'));
    // No caller computes the opening step off the placeholder any more.
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(
        RegExp(r'openingStep\(_?config\)').hasMatch(source),
        isFalse,
        reason: '${entity.path} computes the opening step without the server config',
      );
    }
  });
}
