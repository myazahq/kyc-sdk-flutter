// ─── Address Intelligence config (smart-address capture) ─────────────────────
//
// A smart address is a map pin (+ optional door photo and directions) the
// server corroborates against the evidence it already holds. The result is a
// SOFT sub-result: it never changes the verification's own status, it feeds
// decisioning. So nothing here should block a user beyond what the config
// explicitly requires (`requirePin`, required photo/directions).
//
// On a KYB flow the pin is the BUSINESS PREMISES (checked against the registry
// address) and the photo slot is not offered.
//
// Mirrors the web SDK's address handling and the RN SDK's
// config/addressCollection.ts — keep the three in lockstep.

// The collected address and its JSON live next door (200-line rule), re-exported
// so every existing import of this file keeps working.
export 'address_state.dart';
export 'address_state_json.dart';

class AddressCollectionConfig {
  final bool enabled;

  /// When true the step cannot be skipped (the server also 422s a submission
  /// without a pin).
  final bool requirePin;

  /// Door-photo slot: `'off' | 'optional' | 'required'` (default optional).
  final String? photo;

  /// Directions field: same modes (default optional).
  final String? directions;

  /// The GROUP default for the typed details-sheet fields:
  /// `'off' | 'optional' | 'required'` (default optional). `'required'`
  /// requires the house or flat NUMBER; the building name stays optional.
  /// Resolved per field by address_field_modes.dart, the mirror of the
  /// server's rule: the pin step holds Continue and the review holds Confirm
  /// until every required field shows a value, because the server 422s a
  /// submission that arrives without one.
  final String? propertyFields;

  /// Per-field overrides on the group default, keyed by the typed field
  /// (`propertyName`, `propertyNumber`, `street`, `unit`, `neighbourhood`,
  /// `city`, `state`, `postcode`) with the same three modes. A required field
  /// the applicant leaves on its map prefill is submitted as displayed.
  final Map<String, String> fields;

  /// Street View entrance framing: `'off' | 'optional' | 'required'` (default
  /// optional: on wherever coverage exists, the photo as the fallback;
  /// 'required' removes the Skip affordance while coverage exists, and
  /// no-coverage still falls back). Offered on mobile through the framed
  /// /embed/street-view page in a WebView on the app grant, the way the map
  /// is; see `addressFlowOptions`.
  final String? streetView;

  /// Take a one-shot device GPS fix at Continue — the `attested` tier's
  /// evidence. Best-effort: a denied permission costs the tier, never the flow.
  final bool attestPresence;

  /// Phase 2: multi-day presence verification. When enabled, the SDK stores
  /// the confirmed pin ON-DEVICE so later `MyazaAddressPresence.report()`
  /// calls can evaluate the fence locally — coordinates never leave the phone
  /// after capture.
  final bool presenceEnabled;

  /// OkHi-style always-on monitoring: the server renews each resolved cycle,
  /// and the on-device pin never self-expires.
  final bool presenceAlwaysOn;

  /// The org opts into OS geofencing (and the Android foreground service).
  /// Client-UX only: the intro screen says, once and up front, that an
  /// "allow all the time" prompt is coming. The host app still decides to
  /// call `MyazaBackgroundPresence.enable()` / `MyazaPresenceService.enable()`.
  final bool presenceBackground;

  const AddressCollectionConfig({
    this.enabled = false,
    this.requirePin = false,
    this.photo,
    this.directions,
    this.propertyFields,
    this.fields = const {},
    this.streetView,
    this.attestPresence = false,
    this.presenceEnabled = false,
    this.presenceAlwaysOn = false,
    this.presenceBackground = false,
  });

  factory AddressCollectionConfig.fromJson(Map<String, dynamic> json) {
    final presence = json['presence'];
    return AddressCollectionConfig(
      enabled: json['enabled'] as bool? ?? false,
      requirePin: json['requirePin'] as bool? ?? false,
      photo: json['photo']?.toString(),
      directions: json['directions']?.toString(),
      propertyFields: json['propertyFields']?.toString(),
      fields: _fieldModes(json['fields']),
      streetView: json['streetView']?.toString(),
      attestPresence: json['attestPresence'] as bool? ?? false,
      presenceEnabled: presence is Map && presence['enabled'] == true,
      presenceAlwaysOn: presence is Map && presence['alwaysOn'] == true,
      presenceBackground: presence is Map && presence['background'] == true,
    );
  }
}

/// The per-field mode map, string values only: a wrong-typed entry is dropped
/// so it falls back to the group default rather than breaking the parse.
Map<String, String> _fieldModes(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      }
    : const {};

/// Whether the step is part of the flow.
bool hasAddressCollectionStep(AddressCollectionConfig? config) =>
    config?.enabled == true;

String addressPhotoMode(AddressCollectionConfig? config) =>
    config?.photo ?? 'optional';

String addressDirectionsMode(AddressCollectionConfig? config) =>
    config?.directions ?? 'optional';

// `addressPropertyFieldsOn` and `canContinueAddress` were REMOVED with the
// four-step flow. The first gated a building-name input the details sheet's
// read-only breakdown replaced; the second combined the pin, photo and
// directions into one Continue gate, and the flow no longer works that way:
// the PIN alone gates the pin step, a required photo gates the entrance step,
// and required directions are deliberately not enforced at all (an applicant
// who cannot describe the way in must not be stranded). A helper stating the
// old rule is a trap for whoever wires it back up.

/// Accepted door-photo types — an image, never a PDF.
const List<String> kAddressPhotoMimeTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

bool isAcceptedAddressPhotoMimeType(String? mimeType) {
  final base = (mimeType ?? '').split(';').first.trim().toLowerCase();
  return kAddressPhotoMimeTypes.contains(base);
}
