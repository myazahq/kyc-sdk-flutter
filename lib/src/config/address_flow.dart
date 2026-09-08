import 'dart:math' as math;

import '../providers/kyc_state.dart' show KYCStep;
import '../utils/map_tiles.dart' show MapLatLng;
import 'address_state.dart';

// ─── The address flow, as pure rules ─────────────────────────────────────────
//
// The address capture is REAL steps, not a state machine hidden inside one
// screen: find it (search) → confirm it (the pin) → show it (the entrance) →
// commit it (review). The progress bar advances through them and back/forward
// is ordinary step navigation.
//
// [KYCStep.addressCollection] is the PIN step and keeps its original wire name
// even though it is now the second screen, so session progress saved by older
// builds restores cleanly and the server's step-log titles stay meaningful.
//
// Every constant and decision here is a CROSS-SDK MIRROR of the web SDK's
// steps/address/flow-steps.ts and the RN SDK's lib/address-flow.ts. A drift
// means one platform strands an applicant the other does not, so change all
// three in the same commit.

/// Whether the address vendors are STUBBED rather than called for real.
///
/// SANDBOX mirrors the web SDK's stubbed vendor treatment (user decision
/// 2026-09-03): placeholder map, canned labels, no search loads. The server's
/// sandbox verdicts are canned anyway, so live vendor calls on a test key
/// spend quota for nothing. DEVELOPMENT keeps the real surfaces (the
/// platform's dev-is-real rule); an unknown environment counts as live.
bool addressVendorsStubbed({String? environment}) =>
    environment == 'SANDBOX';

/// The canned pin label every stubbed surface shows: obviously a sample,
/// never a real place. Keep in lockstep with the web and RN SDKs.
const String kSampleAddressLine = '12 Sample Street, Sample City';

/// What the address flow offers, derived once from raw config facts.
class AddressFlowOptions {
  /// A search backend is available AND this is not a builder preview.
  final bool searchAvailable;

  /// The entrance-photo mode: `'off' | 'optional' | 'required'`.
  final String photoMode;

  /// Street View framing is offered: the workflow did not opt out, and a
  /// Google surface exists for it (on mobile, the framed /embed/street-view
  /// page in a WebView on the app grant, the way the map reaches a phone).
  final bool streetViewOffered;

  const AddressFlowOptions({
    required this.searchAvailable,
    required this.photoMode,
    required this.streetViewOffered,
  });
}

/// Derive the flow options from raw config facts.
///
/// ONE builder, read by both the step list and the flow order, so the two can
/// never disagree about which screens exist.
AddressFlowOptions addressFlowOptions({
  String? photo,
  String? streetView,
  required bool serverSearch,
  required bool previewMode,
  required bool hasGoogleKey,
  /// A maps frame URL this mount can render: the framed /embed/street-view
  /// page carries the panorama for it.
  required bool hasStreetViewFrame,
}) =>
    AddressFlowOptions(
      searchAvailable: serverSearch && !previewMode,
      photoMode: photo ?? 'optional',
      // On by default: offered unless the workflow opted out, and wherever a
      // Google surface exists: the in-document browser key (hosted pages) or
      // the framed street-view page (embedded and native mounts).
      streetViewOffered:
          streetView != 'off' && (hasGoogleKey || hasStreetViewFrame),
    );

/// Every step the address flow can contribute, IN FLOW ORDER, whether or not
/// this mount offers it. What "leaving the flow" means is measured against
/// this, so a skip on the search screen lands past the review rather than on
/// the pin; and a resumed session's saved step is ranked against it.
///
/// A list rather than a set because the resume clamp needs to know which
/// offered step sits nearest a saved one. Two literals that had to agree on
/// that order would be one more pair to keep in lockstep.
const List<KYCStep> kAddressFlowOrder = [
  KYCStep.addressSearch,
  KYCStep.addressCollection,
  KYCStep.addressEntrance,
  KYCStep.addressReview,
];

/// The individual flow's address steps, in order. The minimum is the pin and
/// the review: somewhere to place it, and somewhere to commit it.
List<KYCStep> addressFlowSteps(AddressFlowOptions o) => [
      if (o.searchAvailable) KYCStep.addressSearch,
      KYCStep.addressCollection,
      if (o.photoMode != 'off' || o.streetViewOffered) KYCStep.addressEntrance,
      KYCStep.addressReview,
    ];

KYCStep? nextAddressStep(List<KYCStep> steps, KYCStep current) {
  final i = steps.indexOf(current);
  return i >= 0 && i + 1 < steps.length ? steps[i + 1] : null;
}

KYCStep? prevAddressStep(List<KYCStep> steps, KYCStep current) {
  final i = steps.indexOf(current);
  return i > 0 ? steps[i - 1] : null;
}

/// Great-circle metres between two points (small-distance haversine).
double metersBetween(MapLatLng a, MapLatLng b) {
  const r = 6371000.0;
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(b.lat - a.lat);
  final dLng = toRad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(a.lat)) *
          math.cos(toRad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// A map settle within about a metre of the current pin is the tile roundtrip
/// drifting, not a move. Acting on it rebuilt the address WITHOUT its label,
/// and the reverse geocoder then overwrote a searched-and-picked address with
/// the area line, so both axes inside this window are ignored entirely.
const double kPinEpsilon = 1e-5;

/// How far a pin may move from the spot a label was PICKED for before the
/// label stops credibly naming it. The pick names the property; the nudge
/// refines where its roof is. Same scale as the server's at-address tolerance.
const double kKeepPickedLabelRadiusM = 250;

/// Below this, a pin move is roof refinement: keep the picked label silently,
/// because asking would be noise.
const double kLabelPromptMinMoveM = 25;

/// How long to wait after a pin settles before reverse-geocoding it.
const Duration kReverseDebounce = Duration(milliseconds: 700);

/// Whether the pin screen should ASK "keep the selected address?".
///
/// The applicant decides the label's fate; it is never silently discarded and
/// never silently kept against their wishes. Ask once past the refinement
/// threshold. A DERIVED label (no [AddressState.pickedAt] anchor) is never
/// questioned, because those re-derive freely on every move, and an answered
/// "keep" stands until the pin crosses the credibility radius.
bool shouldAskLabelDecision(AddressState address) {
  final picked = address.pickedAt;
  final label = address.label;
  if (picked == null || label == null || label.isEmpty || address.labelKept) {
    return false;
  }
  return metersBetween(
        MapLatLng(picked.lat, picked.lng),
        MapLatLng(address.lat, address.lng),
      ) >
      kLabelPromptMinMoveM;
}

final RegExp _kHouseNumber = RegExp(r'^\d+[a-z]?$', caseSensitive: false);
final RegExp _kWhitespace = RegExp(r'\s+');

/// The address line the flow SHOWS (the pin summary and the review heading).
///
/// The client mirror of the server's composed-line rules, so what the applicant
/// confirms is what the org later reads. A typed number REPLACES a differing
/// picked one, because living at 8 when only 11 was listed is not
/// "8, 11 Bassey Street"; a typed street the label does not carry leads.
String displayAddressLine(AddressState address) {
  final number = _blankToNull(address.propertyNumber);
  final typed = _blankToNull(address.street);
  final label = _blankToNull(address.label);
  final unit = _blankToNull(address.unit);

  // Edit-details corrections ride the tail through a part-wise dedupe,
  // mirroring the server's composed line: identical values vanish, a
  // correction appends beside the map's own answer.
  String withClaims(List<String> parts) {
    final out = [if (unit != null) unit, ...parts];
    bool seen(String v) =>
        out.any((p) => p.toLowerCase() == v.toLowerCase());
    for (final claim in [
      address.neighbourhood,
      address.city,
      address.state,
      address.postcode,
    ]) {
      final t = _blankToNull(claim);
      if (t != null && !seen(t)) out.add(t);
    }
    return out.join(', ');
  }

  if (label == null) {
    if (typed != null) {
      return withClaims([number != null ? '$number $typed' : typed]);
    }
    final claimed = withClaims([]);
    if (claimed.isNotEmpty) return claimed;
    // NEVER coordinates. A moved pin has no line until the reverse geocode
    // answers, and a lat/lng pair is not an address: it read as one for the
    // second before the real line arrived. Empty means "nothing human-readable
    // yet", and the caller shows that it is still coming.
    return '';
  }

  final segs = [
    for (final part in label.split(', '))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  if (typed != null && !label.toLowerCase().contains(typed.toLowerCase())) {
    return withClaims([number != null ? '$number $typed' : typed, ...segs]);
  }

  if (number != null && segs.isNotEmpty) {
    final first = segs.first;
    final firstTokens = first.toLowerCase().split(_kWhitespace);
    final leading = firstTokens.isEmpty ? '' : firstTokens.first;
    if (_kHouseNumber.hasMatch(leading) && leading != number.toLowerCase()) {
      segs[0] = [number, ...first.split(_kWhitespace).skip(1)].join(' ');
    } else if (!firstTokens.contains(number.toLowerCase())) {
      return withClaims([number, ...segs]);
    }
    // Otherwise the label already carries the number: fall through unchanged.
  } else if (number != null) {
    return withClaims([number, ...segs]);
  }

  return withClaims(segs);
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Read to assistive tech while the reverse geocode is out: the pin has a
/// line coming, and a lat/lng pair is not it. Sighted users see a skeleton
/// line in its place (widgets/line_skeleton.dart), never a spinner. Mirrored
/// on the web and RN SDKs.
const String kAddressLinePending = 'Finding the address…';

/// Shown when the geocode came back with nothing. Still not coordinates.
const String kAddressLineUnavailable = 'No address found for this spot';
