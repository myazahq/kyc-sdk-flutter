import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../config/country_adoption.dart';
import '../../config/kyc_config.dart';
import '../../config/scope.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';

// ─── The declared country follows the evidence ───────────────────────────────
//
// The controller's half of config/country_adoption.dart: reads the flow's
// state, asks the pure table, writes the store. Split from the controller
// (200-line rule). Mirrors the RN SDK's adoptGeocodedCountry in
// use-pin-actions.ts and the geo default in use-address-flow.ts.

mixin AddressCountryAdoption {
  // ── Provided by the controller ─────────────────────────────────────────────
  MyazaKYCConfig get config;
  KYCState get state;
  KYCNotifier get notifier;
  bool get alive;

  /// GEOCODED EVIDENCE outranks every GUESS about the declared country; an
  /// explicit pick is never overridden by a geocode; a PICKED address
  /// ([explicit]) replaces even that; the org's accepted list gates all of
  /// it; and outside the address scope only a guessed value is ever touched.
  void adoptGeocodedCountry(String? country, {bool explicit = false}) {
    final decision = adoptionDecision(
      country: country,
      selectedCountry: state.selectedCountry,
      countryAutoPicked: state.countryAutoPicked,
      scope: configScope(config.scope),
      accepted: config.proofOfAddress?.countries,
      explicit: explicit,
    );
    if (decision == null) return;
    if (decision.auto) {
      notifier.setCountryAuto(decision.country);
    } else {
      notifier.setCountry(decision.country);
    }
  }

  /// The address scope's geo default. Runs after the first frame (a provider
  /// must not change while the tree builds) and is a no-op once anything is
  /// declared, so every address step may call it.
  void scheduleGeoDefault() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!alive) return;
      final country = geoDefaultCountry(
        geoCountry: state.serverConfig.geoCountry,
        selectedCountry: state.selectedCountry,
        scope: configScope(config.scope),
        accepted: config.proofOfAddress?.countries,
      );
      if (country != null) notifier.setCountryAuto(country);
    });
  }
}
