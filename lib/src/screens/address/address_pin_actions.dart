import 'package:flutter/foundation.dart';

import '../../config/address_collection.dart';
import '../../services/api_service.dart';
import '../../services/location_failure.dart';
import '../../utils/address_current_location.dart';
import '../../utils/map_tiles.dart';
import 'address_pin_label.dart';
import 'address_pin_move.dart';

// ─── The pin's mechanics ─────────────────────────────────────────────────────
//
// The shared current-location fix and every way the pin can move. Split from
// address_flow_controller.dart per the 200-line rule, exactly as the web SDK
// splits use-pin-actions.ts out of use-address-flow.ts; what a move MEANS is
// pure and lives in address_pin_move.dart, and the reverse geocode that
// labels the pin in address_pin_label.dart.
//
// ONE rule runs through all of it: a HUMAN-CONFIRMED label is never silently
// discarded. The applicant decides its fate, on the pin screen, once.

mixin AddressPinActions on ChangeNotifier, AddressPinLabelling {
  // ── Provided by the controller ─────────────────────────────────────────────
  @override
  KYCApiService get api;
  @override
  AddressState? get address;
  @override
  void writeAddress(AddressState next);
  void setError(String? message);

  /// SANDBOX stubs both vendor paths — the geocoder and the device fix — so a
  /// test key demonstrates the whole flow without a network call or a
  /// permission prompt. See [addressVendorsStubbed].
  @override
  bool get vendorsStubbed;

  CurrentFix? _fix = currentFix();
  bool _locating = locatingCurrentFix();

  // Every async continuation here can outlive the step that started it: the
  // scaffold disposes the controller on step change, the precise fix watches
  // for up to eight seconds, and the controller's reads go through a WidgetRef
  // that throws once its widget unmounts (riverpod's own StateError, an `if`,
  // not an assert). One latch, checked after every await and timer fire, is
  // the whole defence; React's set-state-after-unmount is a no-op, so neither
  // web nor RN needed it, which is exactly why the port missed it.
  bool _alive = true;

  /// Whether the owning step is still mounted; async work checks this before
  /// touching state, the ref, or listeners.
  @override
  bool get alive => _alive;

  /// The device's resolved current address, when a fix has landed.
  CurrentFix? get fix => _fix;

  /// Whether a location attempt is still running.
  bool get locating => _locating;

  void disposePinActions() {
    _alive = false;
    disposeLabelling();
  }

  void _setLocating(bool value) {
    if (!_alive || _locating == value) return;
    _locating = value;
    notifyListeners();
  }

  // ── The shared current-location fix ────────────────────────────────────────

  /// Warm the GPS and its reverse geocode. Safe from every step's mount: the
  /// attempt is shared, so the permission prompt fires at most once.
  void startPrefetch() {
    _setLocating(true);
    prefetchCurrentFix(api, stubbed: vendorsStubbed).then((f) {
      if (!_alive) return;
      _fix = f;
      _locating = false;
      notifyListeners();
      onGeocoded(f?.parts?.country);
    });
  }

  /// Land the pin ON the current fix: the BOOTSTRAP override, used while no
  /// address exists yet. Contrast [locateToPin], which moves an existing pin.
  ///
  /// Sets no `pickedAt`, so the resulting label is treated as derived and
  /// re-derives freely on the next move.
  Future<void> applyCurrentFix({
    VoidCallback? onDone,
    bool silent = false,
  }) async {
    setError(null);
    _setLocating(true);
    // A TAP may retry a previously failed attempt: the applicant may have
    // granted permission since. The silent path never re-prompts.
    final f = await prefetchCurrentFix(api, retry: !silent, stubbed: vendorsStubbed);
    if (!_alive) return;
    _fix = f;
    _setLocating(false);
    onGeocoded(f?.parts?.country);

    // A silent apply resolves seconds after it started, and the applicant may
    // have picked a searched address meanwhile. A late GPS fix must never
    // overwrite a choice they made; an explicit tap still overrides.
    final current = address;
    if (silent && current != null) {
      onDone?.call();
      return;
    }

    if (f != null) {
      writeAddress(
        AddressState.picked(current, lat: f.lat, lng: f.lng).copyWith(
          accuracy: f.accuracy,
          streetView: current?.streetView,
          label: f.label,
          parts: f.parts,
        ),
      );
    } else if (!silent) {
      // Which remedy the person needs depends on WHY the read failed.
      setError(locationFailureMessage(currentFixFailure()));
    }
    onDone?.call();
  }

  /// Move the pin to the current fix, through [setPin] — so a picked address
  /// is protected by the same keep/update prompt as any other move and a
  /// mistaken tap destroys nothing.
  Future<void> locateToPin() async {
    setError(null);
    _setLocating(true);
    final f = await prefetchCurrentFix(api, retry: true, stubbed: vendorsStubbed);
    if (!_alive) return;
    _fix = f;
    _setLocating(false);
    onGeocoded(f?.parts?.country);
    if (f != null) {
      setPin(MapLatLng(f.lat, f.lng), accuracy: f.accuracy);
    } else {
      setError(locationFailureMessage(currentFixFailure()));
    }
  }

  // ── Moving the pin ─────────────────────────────────────────────────────────

  /// The general pin move: a map settle, a locate, a programmatic recentre.
  void setPin(MapLatLng next, {double? accuracy}) {
    final move = resolvePinMove(address, next, accuracy: accuracy);
    final result = move.address;
    if (result == null) return;
    writeAddress(result);
    if (move.relabel) labelPin(next.lat, next.lng);
  }

  /// The applicant keeps the picked label despite the moved pin.
  void keepPickedLabel() {
    final current = address;
    if (current != null) writeAddress(current.copyWith(labelKept: true));
  }

  /// The applicant adopts the PIN's own address: drop the pick, re-derive now.
  void adoptPinAddress() {
    final current = address;
    if (current == null) return;
    writeAddress(current.copyWith(clearPickedLabel: true));
    labelPin(current.lat, current.lng, delay: Duration.zero);
  }

  /// Label a restored pin that has none (a session saved before labels
  /// existed) rather than showing raw coordinates.
  void relabelPin() {
    final current = address;
    if (current != null && (current.label ?? '').isEmpty) {
      labelPin(current.lat, current.lng, delay: Duration.zero);
    }
  }
}
