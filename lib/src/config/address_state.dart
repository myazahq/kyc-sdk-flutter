import '../services/api_service.dart' show AddressParts;

// ─── The smart address the flow collects ─────────────────────────────────────
//
// One nullable object: the pin, what the applicant typed, what a pick or a
// reverse geocode resolved, and the attest-presence device fix taken at
// confirm. Split from address_collection.dart (200-line rule); the JSON in and
// out of it lives in address_state_json.dart.
//
// One rule runs through the whole flow and shapes this model: a HUMAN-CONFIRMED
// label is never silently discarded. That is what [pickedAt] and [labelKept]
// exist for, and why neither ever reaches the wire.
//
// Mirrors the web SDK's KYCState.address and the RN SDK's address state — keep
// the three in lockstep.

/// Where a label was PICKED for (a search selection's own coordinates).
///
/// Presence means the label is human-confirmed, so it survives pin nudges
/// instead of being re-derived on every drag. Absent means the label came from
/// a reverse geocode, which re-derives freely. Never on the wire.
class AddressPickedAt {
  final double lat;
  final double lng;

  const AddressPickedAt(this.lat, this.lng);
}

/// A Street View entrance frame: coordinates only, so the server fetches the
/// image with its own key. Captured here through the framed
/// /embed/street-view page in a WebView (FramedStreetView), and also restored
/// from a session begun on a hosted page.
class AddressStreetView {
  final String panoId;
  final double heading;
  final double pitch;
  final double fov;

  const AddressStreetView({
    required this.panoId,
    required this.heading,
    required this.pitch,
    required this.fov,
  });

  Map<String, dynamic> toJson() => {
        'panoId': panoId,
        'heading': heading,
        'pitch': pitch,
        'fov': fov,
      };
}

class AddressState {
  final double lat;
  final double lng;

  /// Accuracy of a GPS-sourced pin (metres); null for a dragged pin.
  final double? accuracy;

  final String directions;

  /// Building or estate name — back on the edit-details form (user decision
  /// 2026-08-31: everything editable, OkHi-style).
  final String propertyName;
  final String propertyNumber;

  /// A street the applicant TYPED. Prefilled from the map's answer in the
  /// edit-details sheet; stored only once the applicant edits it. Null means
  /// never touched (the prefill shows), '' means deliberately cleared — the
  /// distinction is what stops a wrong prefill refilling under the cursor.
  final String? street;

  /// The rest of the OkHi-style edit-details form: unit + area/region
  /// corrections. Same null/''/value semantics as [street]; all applicant
  /// claims, never fed into corroboration by the server.
  final String? unit;
  final String? neighbourhood;
  final String? city;
  final String? state;
  final String? postcode;

  /// The pin's human-readable line, from a search pick or a reverse geocode.
  /// Sent with the submission as the applicant-confirmed line: the server
  /// prefers it over its own reverse geocode, whose coverage drops whole
  /// streets in our markets.
  final String? label;

  /// The label broken down. Display only, like [label].
  final AddressParts? parts;

  final AddressPickedAt? pickedAt;

  /// The applicant explicitly chose to KEEP the picked label after moving the
  /// pin. Reset when the pin crosses the credibility radius, so the question is
  /// asked again exactly once out there. Never on the wire.
  final bool labelKept;

  final AddressStreetView? streetView;

  final double? deviceLat;
  final double? deviceLng;
  final double? deviceAccuracy;
  final String? capturedAt;

  const AddressState({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.directions = '',
    this.propertyName = '',
    this.propertyNumber = '',
    this.street,
    this.unit,
    this.neighbourhood,
    this.city,
    this.state,
    this.postcode,
    this.label,
    this.parts,
    this.pickedAt,
    this.labelKept = false,
    this.streetView,
    this.deviceLat,
    this.deviceLng,
    this.deviceAccuracy,
    this.capturedAt,
  });

  /// The base shape after a pick or a bootstrap locate: the pin lands on the
  /// hit, the applicant's typed fields survive, and the house number prefills
  /// ONLY when they have not typed one — their word always beats the map's.
  ///
  /// Deliberately drops [label], [parts], [pickedAt], [labelKept] and
  /// [streetView]: callers re-add whatever should survive, explicitly.
  factory AddressState.picked(
    AddressState? prev, {
    required double lat,
    required double lng,
    String? houseNumber,
  }) {
    final typedNumber = prev?.propertyNumber.trim() ?? '';
    return AddressState(
      lat: lat,
      lng: lng,
      directions: prev?.directions ?? '',
      propertyName: prev?.propertyName ?? '',
      propertyNumber:
          typedNumber.isNotEmpty ? prev!.propertyNumber : (houseNumber ?? ''),
      street: prev?.street,
      unit: prev?.unit,
      neighbourhood: prev?.neighbourhood,
      city: prev?.city,
      state: prev?.state,
      postcode: prev?.postcode,
    );
  }

  AddressState copyWith({
    double? lat,
    double? lng,
    double? accuracy,
    String? directions,
    String? propertyName,
    String? propertyNumber,
    String? street,
    String? unit,
    String? neighbourhood,
    String? city,
    String? state,
    String? postcode,
    String? label,
    AddressParts? parts,
    AddressPickedAt? pickedAt,
    bool? labelKept,
    AddressStreetView? streetView,
    double? deviceLat,
    double? deviceLng,
    double? deviceAccuracy,
    String? capturedAt,
    // Adopting the pin's own address drops the human-confirmed pick whole:
    // the line, its breakdown, the anchor and the answered "keep" are one
    // decision, so they are cleared together rather than four flags deep.
    bool clearPickedLabel = false,
    // A DRAGGED pin is no longer GPS-sourced, so its accuracy has to go with
    // the coordinates it described. Carrying the old figure forward would
    // submit a precision claim about a spot nothing measured.
    bool clearAccuracy = false,
    // A RESOLVED street retires the typed one back to NULL, never '': the
    // details sheet reads '' as deliberately cleared, which suppressed the
    // resolved-street prefill it should be showing.
    bool clearStreet = false,
  }) =>
      AddressState(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        accuracy: clearAccuracy ? null : (accuracy ?? this.accuracy),
        directions: directions ?? this.directions,
        propertyName: propertyName ?? this.propertyName,
        propertyNumber: propertyNumber ?? this.propertyNumber,
        street: clearStreet ? null : (street ?? this.street),
        unit: unit ?? this.unit,
        neighbourhood: neighbourhood ?? this.neighbourhood,
        city: city ?? this.city,
        state: state ?? this.state,
        postcode: postcode ?? this.postcode,
        label: clearPickedLabel ? null : (label ?? this.label),
        parts: clearPickedLabel ? null : (parts ?? this.parts),
        pickedAt: clearPickedLabel ? null : (pickedAt ?? this.pickedAt),
        labelKept: clearPickedLabel ? false : (labelKept ?? this.labelKept),
        streetView: streetView ?? this.streetView,
        deviceLat: deviceLat ?? this.deviceLat,
        deviceLng: deviceLng ?? this.deviceLng,
        deviceAccuracy: deviceAccuracy ?? this.deviceAccuracy,
        capturedAt: capturedAt ?? this.capturedAt,
      );
}
