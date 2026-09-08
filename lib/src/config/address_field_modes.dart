import 'address_collection.dart';

// ─── Per-field modes for the typed details-sheet fields ──────────────────────
//
// The CLIENT MIRROR of the server's lib/workflows/address-fields.ts
// (kyc-core) and of the web and RN SDKs' address-field-modes modules. Keep the
// resolution rule in lockstep: the legacy `propertyFields` group switch is the
// default for every typed field, `propertyFields: 'required'` requires the
// house/flat NUMBER, and `fields.<key>` overrides per key. The three mirrors
// share one vector file (test/address_field_modes_vectors.json).
//
// Why it matters here: the server 422s a submission whose required fields
// never arrived. Without this mirror a mobile applicant walked the whole flow
// and the refusal landed on the last screen with nothing to act on.

enum AddressFieldMode {
  off,
  optional,
  required;

  static AddressFieldMode? parse(String? value) => switch (value) {
        'off' => off,
        'optional' => optional,
        'required' => required,
        _ => null,
      };
}

const List<String> kAddressFieldKeys = [
  'propertyName',
  'propertyNumber',
  'street',
  'unit',
  'neighbourhood',
  'city',
  'state',
  'postcode',
];

const Map<String, String> kAddressFieldLabels = {
  'propertyName': 'Building name',
  'propertyNumber': 'House or flat number',
  'street': 'Street name',
  'unit': 'Unit',
  'neighbourhood': 'Neighbourhood',
  'city': 'City',
  'state': 'State',
  'postcode': 'Area code',
};

Map<String, AddressFieldMode> addressFieldModes(
    AddressCollectionConfig? config) {
  final group = AddressFieldMode.parse(config?.propertyFields) ??
      AddressFieldMode.optional;
  return {
    for (final key in kAddressFieldKeys)
      key: AddressFieldMode.parse(config?.fields[key]) ??
          (group == AddressFieldMode.off
              ? AddressFieldMode.off
              : group == AddressFieldMode.required && key == 'propertyNumber'
                  ? AddressFieldMode.required
                  : AddressFieldMode.optional),
  };
}

/// What the applicant TYPED for a field: null when never touched (the map's
/// prefill shows), '' when deliberately cleared.
String? _typed(String key, AddressState address) => switch (key) {
      'propertyName' => address.propertyName,
      'propertyNumber' => address.propertyNumber,
      'street' => address.street,
      'unit' => address.unit,
      'neighbourhood' => address.neighbourhood,
      'city' => address.city,
      'state' => address.state,
      'postcode' => address.postcode,
      _ => null,
    };

/// Which map-prefill part fills each field while untouched (the sheet's own
/// rule). Property name/number and unit have no prefill: the applicant alone
/// can know them.
String? _prefill(String key, AddressState address) => switch (key) {
      'street' => address.parts?.street,
      'neighbourhood' => address.parts?.area,
      'city' => address.parts?.city,
      'state' => address.parts?.state,
      'postcode' => address.parts?.postcode,
      _ => null,
    };

/// The value the sheet DISPLAYS for a field: typed wins (a cleared field
/// stays cleared), else the map's prefill.
String displayedAddressValue(String key, AddressState address) {
  final typed = _typed(key, address)?.trim();
  if (typed != null) return typed;
  return (_prefill(key, address) ?? '').trim();
}

/// Required fields whose DISPLAYED value is blank: what holds Continue.
List<String> missingRequiredAddressFields(
    AddressCollectionConfig? config, AddressState? address) {
  if (address == null) return const [];
  final modes = addressFieldModes(config);
  return [
    for (final key in kAddressFieldKeys)
      if (modes[key] == AddressFieldMode.required &&
          displayedAddressValue(key, address).isEmpty)
        key,
  ];
}

/// The nudge under Continue when required fields are still blank.
String missingFieldsNudge(List<String> missing) =>
    'This flow needs: ${missing.map((k) => kAddressFieldLabels[k]!.toLowerCase()).join(', ')}.';

/// The map-prefill values a REQUIRED field rides to the server when the
/// applicant left it untouched: they saw it filled and confirmed it by
/// continuing, so the wire must carry it. Typed values are absent here on
/// purpose (the payload already sends them), so spreading this after them
/// overrides nothing.
Map<String, String> requiredPrefillSubmission(
    AddressCollectionConfig? config, AddressState address) {
  final modes = addressFieldModes(config);
  final out = <String, String>{};
  for (final key in kAddressFieldKeys) {
    if (modes[key] != AddressFieldMode.required) continue;
    final typed = _typed(key, address)?.trim() ?? '';
    if (typed.isNotEmpty) continue;
    final displayed = displayedAddressValue(key, address);
    if (displayed.isNotEmpty) out[key] = displayed;
  }
  return out;
}
