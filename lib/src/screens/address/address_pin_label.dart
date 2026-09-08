import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../config/address_collection.dart';
import '../../config/address_flow.dart';
import '../../services/api_service.dart';

// ─── Reverse geocoding: the pin's human-readable line ────────────────────────
//
// Split from address_pin_actions.dart (200-line rule). Debounced, because a
// drag settles several times, and DROPPED when the pin moved again meanwhile:
// the comparison is exact coordinate equality, so a late answer can never
// label somewhere the applicant has already left. Failures are swallowed; the
// line is a convenience. Mirrors the RN SDK's use-label-pin.ts.

mixin AddressPinLabelling on ChangeNotifier {
  // ── Provided by the controller ─────────────────────────────────────────────
  KYCApiService get api;
  AddressState? get address;
  void writeAddress(AddressState next);
  bool get vendorsStubbed;
  bool get alive;

  /// A reverse geocode answered with the pin's own country: the declared
  /// country may follow it (address_country_adoption.dart).
  void onGeocoded(String? country);

  Timer? _reverseTimer;

  bool _labelling = false;

  /// A reverse geocode is out: the pin has no line YET, rather than none. The
  /// summary shows nothing while a pin is unread (never coordinates), so it
  /// has to say which of the two it is.
  bool get labelling => _labelling;

  void _setLabelling(bool value) {
    if (_labelling == value) return;
    _labelling = value;
    notifyListeners();
  }

  void disposeLabelling() {
    _reverseTimer?.cancel();
    _reverseTimer = null;
  }

  /// Reverse-geocode the pin and adopt the line it comes back with.
  void labelPin(double lat, double lng, {Duration delay = kReverseDebounce}) {
    _reverseTimer?.cancel();
    _setLabelling(true);
    // SANDBOX never reverse-geocodes: the sample line demonstrates the summary
    // card with no network call (the web SDK's stubbed-vendor rule).
    if (vendorsStubbed) {
      _reverseTimer = Timer(Duration.zero, () {
        if (!alive) return;
        final current = address;
        if (current == null ||
            current.lat != lat ||
            current.lng != lng ||
            (current.label ?? '').isNotEmpty) {
          return;
        }
        writeAddress(current.copyWith(label: kSampleAddressLine));
        _setLabelling(false);
      });
      return;
    }
    _reverseTimer = Timer(delay, () async {
      AddressReverseResult result;
      try {
        result = await api.addressReverse(lat, lng);
      } catch (_) {
        _setLabelling(false);
        return;
      }
      if (!alive) return;
      _setLabelling(false);
      final line = result.line;
      final current = address;
      if (line == null ||
          line.isEmpty ||
          current == null ||
          current.lat != lat ||
          current.lng != lng) {
        return;
      }
      writeAddress(current.copyWith(
        label: line,
        parts: result.parts,
        // A RESOLVED street retires the typed one: that input only existed
        // because no source knew the street, and a hidden field must not keep
        // leading the composed line. Cleared to NULL so the sheet prefills
        // the resolved street instead of showing a "cleared" empty field.
        clearStreet: (result.parts?.street ?? '').trim().isNotEmpty,
      ));
      onGeocoded(result.parts?.country);
    });
  }
}
