import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/address_collection.dart';
import '../../config/address_flow.dart';
import '../../config/kyc_config.dart';
import '../../presence/presence_store.dart';
import '../../providers/address_step_order.dart';
import '../../providers/kyc_provider.dart';
import '../../providers/kyc_state.dart';
import '../../providers/step_order.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../utils/map_tiles.dart';
import 'address_country_adoption.dart';
import 'address_photo_actions.dart';
import 'address_pin_actions.dart';
import 'address_pin_label.dart';

// ─── The address flow's shared brain ─────────────────────────────────────────
//
// Every address step mounts one of these and gets the same derived flags, the
// same step list and the same actions — which is what keeps four separate
// screens telling one story. Per-screen like the web SDK's useAddressFlow: the
// ADDRESS itself lives in KYCState, so only the transient flags are local.
//
// Navigation deliberately routes through the ordinary step order rather than
// its own state machine: these are real steps, so the progress bar advances
// through them and the header's back arrow already does the right thing.

class AddressFlowController extends ChangeNotifier
    with
        AddressPinLabelling,
        AddressPinActions,
        AddressCountryAdoption,
        AddressPhotoActions {
  AddressFlowController(this._ref) {
    // The address scope's IP default, once, while nothing is declared.
    scheduleGeoDefault();
  }

  final WidgetRef _ref;

  bool _confirming = false;
  String? _error;

  bool get confirming => _confirming;
  String? get error => _error;

  @override
  void dispose() {
    disposePinActions();
    super.dispose();
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  @override
  MyazaKYCConfig get config => _ref.read(kycConfigProvider);
  @override
  KYCNotifier get notifier => _ref.read(kYCNotifierProvider.notifier);
  @override
  KYCState get state => _ref.read(kYCNotifierProvider);

  /// A reverse geocode of the fix or the pin: the declared country follows
  /// the evidence (address_country_adoption.dart).
  @override
  void onGeocoded(String? country) => adoptGeocodedCountry(country);

  @override
  KYCApiService get api => notifier.api;

  @override
  AddressState? get address => state.address;

  @override
  bool get vendorsStubbed =>
      addressVendorsStubbed(environment: state.serverConfig.environment);

  AddressCollectionConfig? get cfg => config.addressCollection;

  bool get isBusiness => config.subjectType == 'business';

  MapLatLng? get pin {
    final a = address;
    return a == null ? null : MapLatLng(a.lat, a.lng);
  }

  /// A KYB flow's pin is the BUSINESS PREMISES, so the country that centres
  /// the map is the registry's, not the applicant's.
  String? get country => isBusiness
      ? (state.businessCountry ?? config.business?.country)
      : effectiveCountry(config, state);

  ({MapLatLng center, int zoom}) get view => defaultMapView(country);

  /// The address steps this mount offers.
  List<KYCStep> get steps => addressStepsFor(config, state);

  /// Whether [step] is the last address step this flow offers, so its Continue
  /// is the COMMIT rather than an advance.
  ///
  /// Derived from the flow's own step list rather than asserted from the
  /// subject type. Today only KYB ends on the pin, so `isBusiness` would give
  /// the same answer — but it answers a different question, and a flow that
  /// ever ended somewhere else would silently stop taking the attest fix and
  /// storing the presence pin, with nothing to show for it.
  bool isLastAddressStep(KYCStep step) => nextAddressStep(steps, step) == null;

  /// The entrance photo's mode. KYB never offers the slot: the premises pin
  /// and its directions are the capture, and the server's business path
  /// carries no address photo.
  String get photoMode => isBusiness ? 'off' : addressPhotoMode(cfg);

  /// Street View framing is offered: the workflow did not opt out and the
  /// server minted a maps frame URL, which the framed /embed/street-view page
  /// rides in a WebView on the app grant (address_step_order.dart).
  bool get streetViewOffered =>
      !isBusiness && addressFlowOptionsFor(config, state).streetViewOffered;

  /// Whether this step should show the presence primer instead of its body.
  bool showIntroGate(KYCStep step) =>
      addressIntroGateShowing(config, state, step);

  // ── Writes ─────────────────────────────────────────────────────────────────

  @override
  void writeAddress(AddressState next) => notifier.setAddress(next);

  @override
  void setError(String? message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  /// Patch the collected address in place. A no-op without a pin: every field
  /// the sheet edits describes a place, and there is no place yet.
  void patchAddress(AddressState Function(AddressState) patch) {
    final current = address;
    if (current != null) writeAddress(patch(current));
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// The next step in the flow, else out of it. Both are the same move here,
  /// because the address steps sit in the ordinary step order.
  void goNext() => notifier.nextStep();

  /// The previous step, else back out of the flow entirely.
  void goBack() => notifier.previousStep();

  /// Leave the address flow FORWARDS: after the review, after a KYB commit, or
  /// on a skip.
  ///
  /// Measured against every step the flow could contribute rather than the one
  /// in hand, so a skip on the search screen lands past the review instead of
  /// on the pin.
  void exitForward() {
    final order = buildStepOrder(config, state);
    final last = order.lastIndexWhere(kAddressFlowOrder.contains);
    if (last < 0 || last + 1 >= order.length) return;
    notifier.goToStep(order[last + 1]);
  }

  /// Commit: the one-shot attest fix (best-effort), the on-device presence pin,
  /// then leave the flow.
  Future<void> confirm() async {
    final current = address;
    if (current == null) return;
    _confirming = true;
    notifyListeners();

    if (cfg?.attestPresence == true) {
      final fixed = await withDeviceFix(current);
      if (!alive) return;
      writeAddress(fixed);
    }
    // Presence verification keeps the confirmed pin ON-DEVICE so later
    // foreground reports evaluate the fence locally. Keyed by the org's user
    // reference: without one there is nothing to report against.
    final userId = config.userId;
    if (cfg?.presenceEnabled == true && userId != null && userId.isNotEmpty) {
      await savePresencePin(userId, current.lat, current.lng,
          alwaysOn: cfg?.presenceAlwaysOn == true);
    }
    if (!alive) return;

    _confirming = false;
    notifyListeners();
    exitForward();
  }
}
