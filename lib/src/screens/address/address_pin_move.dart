import '../../config/address_collection.dart';
import '../../config/address_flow.dart';
import '../../services/api_service.dart';
import '../../utils/map_tiles.dart';

// ─── What a pin move, or a pick, means ───────────────────────────────────────
//
// The pure half of the flow's two writes: given where the pin was and where it
// landed (or which candidate the applicant chose), what the address becomes.
// Extracted so the rules can be tested without a map, a widget or a network
// call, and because this is the one place the flow decides the fate of a
// human-confirmed label.

/// The outcome of a pin move.
class PinMove {
  /// The address to write, or null when the move should be IGNORED entirely.
  final AddressState? address;

  /// Whether the new pin needs a fresh reverse geocode. False when a picked
  /// label survived the move: it already names the place, and re-deriving
  /// would overwrite the applicant's own choice.
  final bool relabel;

  const PinMove({this.address, this.relabel = false});

  /// The settle that was not a move.
  static const PinMove ignored = PinMove();
}

/// Resolve a pin move against the address in hand.
///
/// Three outcomes, in order:
///
///  1. Inside the epsilon on BOTH axes: a map settle within about a metre of
///     the current pin is the tile roundtrip drifting, not a move. Acting on
///     it rebuilt the address WITHOUT its label, and the reverse geocoder then
///     overwrote a searched-and-picked address with the area line.
///  2. A PICKED label survives: the pick names the property, the nudge refines
///     where its roof is. The applicant decides the label's fate later, on the
///     pin screen. Crossing the credibility radius only resets an answered
///     "keep", so the question is asked again exactly once out there.
///  3. Otherwise rebuild: typed fields and a captured Street View frame
///     survive, and a DERIVED label dies with the spot it described.
PinMove resolvePinMove(
  AddressState? current,
  MapLatLng next, {
  double? accuracy,
}) {
  if (current != null &&
      (current.lat - next.lat).abs() < kPinEpsilon &&
      (current.lng - next.lng).abs() < kPinEpsilon) {
    return PinMove.ignored;
  }

  final picked = current?.pickedAt;
  if (current != null && picked != null && (current.label ?? '').isNotEmpty) {
    final beyond = metersBetween(
          MapLatLng(picked.lat, picked.lng),
          next,
        ) >
        kKeepPickedLabelRadiusM;
    return PinMove(
      address: current.copyWith(
        lat: next.lat,
        lng: next.lng,
        accuracy: accuracy,
        clearAccuracy: accuracy == null,
        labelKept: beyond && current.labelKept ? false : null,
      ),
    );
  }

  return PinMove(
    address: AddressState.picked(current, lat: next.lat, lng: next.lng)
        .copyWith(accuracy: accuracy, streetView: current?.streetView),
    relabel: true,
  );
}

/// The address after the applicant PICKS a search candidate.
///
/// [AddressState.pickedAt] is what makes the resulting label human-confirmed,
/// which is why it is set here and never from a reverse geocode: a picked line
/// survives later pin nudges, a derived one re-derives freely.
AddressState addressFromPick(AddressState? current, ResolvedPlace place) {
  final formatted = (place.formatted ?? '').trim();
  return AddressState.picked(
    current,
    lat: place.lat,
    lng: place.lng,
    houseNumber: place.houseNumber,
  ).copyWith(
    label: formatted.isEmpty ? null : formatted,
    pickedAt: formatted.isEmpty
        ? null
        : AddressPickedAt(place.lat, place.lng),
    // A pick that RESOLVES a street retires the typed one: that input only
    // existed because no source knew the street, and a hidden field must not
    // keep leading the composed line. Cleared to NULL so the sheet prefills
    // the resolved street instead of showing a "cleared" empty field.
    clearStreet: (place.road ?? '').trim().isNotEmpty,
    // Places picks carry the breakdown; basic hits fall back to the label.
    parts: place.hasParts ? place.parts : null,
  );
}
