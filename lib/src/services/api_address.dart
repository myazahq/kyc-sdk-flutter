part of 'api_service.dart';

// ─── Address Intelligence API types ──────────────────────────────────────────
//
// The four address endpoints the flow reads: forward search (basic), reverse
// geocode, Places autocomplete, and place details. Every one of them may fail,
// and every failure degrades to "place the pin by hand" — never to a blocked
// flow.
//
// A `part` rather than a sibling library (contrast api_business.dart) because
// the calls in api_address_calls.dart need the library-private Dio client and
// error mapper; a plain extension in another library cannot reach them, and
// api_service.dart is already far past the 200-line rule.
//
// Mirrors the web SDK's services/api.ts address types — keep them in lockstep.

/// Reads a JSON value as a string, or null when the key is absent or carries
/// something else. Wire shapes are declarations, never validation: a stray
/// number must not throw inside a display-only lookup.
String? _addressString(Object? value) => value is String ? value : null;

double? _addressDouble(Object? value) =>
    value is num ? value.toDouble() : null;

/// The pin's address broken down — what the details sheet shows as rows.
/// Display only: it never reaches the wire on a submission.
class AddressParts {
  final String? street;
  final String? area;
  final String? city;
  final String? state;
  final String? postcode;

  /// ISO-2 of the pin's OWN country, from the geocoder. On the address scope
  /// the declared country follows it (config/country_adoption.dart); it is
  /// never a row in the sheet, which shows the country the flow declared.
  final String? country;

  const AddressParts({
    this.street,
    this.area,
    this.city,
    this.state,
    this.postcode,
    this.country,
  });

  factory AddressParts.fromJson(Map<String, dynamic> json) => AddressParts(
        street: _addressString(json['street']),
        area: _addressString(json['area']),
        city: _addressString(json['city']),
        state: _addressString(json['state']),
        postcode: _addressString(json['postcode']),
        country: _addressString(json['country']),
      );

  bool get isEmpty =>
      street == null &&
      area == null &&
      city == null &&
      state == null &&
      postcode == null &&
      country == null;

  /// Written into session progress so a resumed attempt still shows the
  /// breakdown. Nulls are kept: a restored `parts` with five null rows and an
  /// absent `parts` mean the same thing to the sheet.
  Map<String, dynamic> toJson() => {
        'street': street,
        'area': area,
        'city': city,
        'state': state,
        'postcode': postcode,
        'country': country,
      };
}

/// `GET /address/reverse` — the pin's human-readable line. Display only.
class AddressReverseResult {
  final String? line;
  final String? road;
  final AddressParts? parts;

  const AddressReverseResult({this.line, this.road, this.parts});

  factory AddressReverseResult.fromJson(Map<String, dynamic> json) {
    final parts = json['parts'];
    return AddressReverseResult(
      line: _addressString(json['line']),
      road: _addressString(json['road']),
      parts: parts is Map
          ? AddressParts.fromJson(parts.cast<String, dynamic>())
          : null,
    );
  }
}

/// One candidate from the basic forward search (explicit submit only).
class AddressSearchHit {
  final String label;
  final double lat;
  final double lng;
  final String? houseNumber;
  final String? road;

  /// ISO-2 of the hit's own country (the declaration derives from it).
  final String? country;

  const AddressSearchHit({
    required this.label,
    required this.lat,
    required this.lng,
    this.houseNumber,
    this.road,
    this.country,
  });

  static AddressSearchHit? fromJson(Map<String, dynamic> json) {
    final lat = _addressDouble(json['lat']);
    final lng = _addressDouble(json['lng']);
    // A hit with no coordinates cannot land a pin, which is the only thing
    // picking one does. Dropped rather than offered.
    if (lat == null || lng == null) return null;
    return AddressSearchHit(
      label: _addressString(json['label']) ?? '',
      lat: lat,
      lng: lng,
      houseNumber: _addressString(json['houseNumber']),
      road: _addressString(json['road']),
      country: _addressString(json['country']),
    );
  }
}

/// One Places autocomplete suggestion. Resolving it to coordinates is a
/// separate call, which is also what closes the billing session.
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  static PlaceSuggestion? fromJson(Map<String, dynamic> json) {
    final placeId = _addressString(json['placeId']);
    if (placeId == null || placeId.isEmpty) return null;
    return PlaceSuggestion(
      placeId: placeId,
      mainText: _addressString(json['mainText']) ?? '',
      secondaryText: _addressString(json['secondaryText']) ?? '',
    );
  }
}

/// A picked suggestion, resolved to coordinates plus the structured pieces the
/// details sheet renders.
class ResolvedPlace {
  final double lat;
  final double lng;
  final String? houseNumber;
  final String? road;
  final String? formatted;
  final String? area;
  final String? city;
  final String? state;
  final String? postcode;

  /// ISO-2 of the picked address's own country — the declaration derives
  /// from it on the address scope (a pick is the applicant's own statement).
  final String? country;

  const ResolvedPlace({
    required this.lat,
    required this.lng,
    this.houseNumber,
    this.road,
    this.formatted,
    this.area,
    this.city,
    this.state,
    this.postcode,
    this.country,
  });

  factory ResolvedPlace.fromJson(Map<String, dynamic> json) => ResolvedPlace(
        lat: _addressDouble(json['lat']) ?? 0,
        lng: _addressDouble(json['lng']) ?? 0,
        houseNumber: _addressString(json['houseNumber']),
        road: _addressString(json['road']),
        formatted: _addressString(json['formatted']),
        area: _addressString(json['area']),
        city: _addressString(json['city']),
        state: _addressString(json['state']),
        postcode: _addressString(json['postcode']),
        country: _addressString(json['country']),
      );

  /// Whether the resolved place carries any structured breakdown at all, so a
  /// caller can skip writing an all-null `parts`.
  bool get hasParts =>
      road != null ||
      area != null ||
      city != null ||
      state != null ||
      postcode != null ||
      country != null;

  AddressParts get parts => AddressParts(
        street: road,
        area: area,
        city: city,
        state: state,
        postcode: postcode,
        country: country,
      );
}
