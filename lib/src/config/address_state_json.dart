import '../services/api_service.dart' show AddressParts;
import 'address_collection.dart' show AddressCollectionConfig;
import 'address_field_modes.dart' show requiredPrefillSubmission;
import 'address_state.dart';

// ─── The address on the wire, in progress, and back ──────────────────────────
//
// Three shapes, deliberately not one:
//
//   • addressPayload      — the SUBMISSION. Only what the server acts on.
//   • addressProgressJson — the session snapshot. The whole object, so a resume
//                           restores the pick and its breakdown too.
//   • addressFromProgress — the restore, type-coerced field by field.
//
// The snapshot was written by WHATEVER build saved it, so every field is
// checked on the way back in and a wrong-typed one is dropped. A partial
// snapshot degrades to restoring less, never to breaking the flow.

/// The wire block the verify body carries.
///
/// [AddressState.pickedAt], [AddressState.labelKept] and [AddressState.parts]
/// are display-side reasoning about the label, not facts about the address, so
/// they never leave the device. The device fix goes only as a PAIR: a latitude
/// without its longitude places nobody.
///
/// [config] is the flow's address step: a workflow-REQUIRED field the
/// applicant left on its map prefill rides that prefill (they saw it filled
/// and confirmed by continuing, and the server 422s a required field that
/// never arrives). Session progress passes none and stays raw, so a resume
/// never confuses a prefill with a claim.
Map<String, dynamic> addressPayload(AddressState address,
    {AddressCollectionConfig? config}) {
  final hasDeviceFix = address.deviceLat != null && address.deviceLng != null;
  final label = address.label?.trim() ?? '';
  return {
    'lat': address.lat,
    'lng': address.lng,
    if (label.isNotEmpty) 'label': label,
    if (address.accuracy != null) 'accuracy': address.accuracy,
    if (address.directions.trim().isNotEmpty)
      'directions': address.directions.trim(),
    if (address.propertyName.trim().isNotEmpty)
      'propertyName': address.propertyName.trim(),
    if (address.propertyNumber.trim().isNotEmpty)
      'propertyNumber': address.propertyNumber.trim(),
    if ((address.street ?? '').trim().isNotEmpty)
      'street': address.street!.trim(),
    // The rest of the edit-details form: claims, sent only when typed.
    if ((address.unit ?? '').trim().isNotEmpty) 'unit': address.unit!.trim(),
    if ((address.neighbourhood ?? '').trim().isNotEmpty)
      'neighbourhood': address.neighbourhood!.trim(),
    if ((address.city ?? '').trim().isNotEmpty) 'city': address.city!.trim(),
    if ((address.state ?? '').trim().isNotEmpty)
      'state': address.state!.trim(),
    if ((address.postcode ?? '').trim().isNotEmpty)
      'postcode': address.postcode!.trim(),
    // Required-but-untouched prefills, LAST among the typed fields: the helper
    // never carries a typed value, so nothing above is overridden.
    ...requiredPrefillSubmission(config, address),
    if (address.streetView != null) 'streetView': address.streetView!.toJson(),
    if (hasDeviceFix) ...{
      'deviceLat': address.deviceLat,
      'deviceLng': address.deviceLng,
      if (address.deviceAccuracy != null)
        'deviceAccuracy': address.deviceAccuracy,
      if (address.capturedAt != null) 'capturedAt': address.capturedAt,
    },
  };
}

/// The whole address as session progress stores it.
///
/// Richer than the wire payload on purpose: a placed pin is work done, and a
/// resume that showed raw coordinates where the applicant's picked address had
/// been would make them do the search again.
Map<String, dynamic> addressProgressJson(AddressState address) => {
      ...addressPayload(address),
      if (address.parts != null) 'parts': address.parts!.toJson(),
      if (address.pickedAt != null)
        'pickedAt': {
          'lat': address.pickedAt!.lat,
          'lng': address.pickedAt!.lng,
        },
      if (address.labelKept) 'labelKept': true,
    };

double? _double(Object? value) => value is num ? value.toDouble() : null;

String _string(Object? value) => value is String ? value : '';

/// The stored address, when the snapshot carries a readable pin.
///
/// The pin is the guard: without both coordinates there is nothing to restore
/// and half an address is worse than none. The device fix is deliberately NOT
/// restored — it is evidence of standing somewhere at a MOMENT, so it is taken
/// fresh at confirm rather than resurrected from an older session.
AddressState? addressFromProgressJson(Object? raw) {
  if (raw is! Map) return null;
  final lat = _double(raw['lat']);
  final lng = _double(raw['lng']);
  if (lat == null || lng == null) return null;

  final rawParts = raw['parts'];
  final rawPickedAt = raw['pickedAt'];
  final pickedLat = rawPickedAt is Map ? _double(rawPickedAt['lat']) : null;
  final pickedLng = rawPickedAt is Map ? _double(rawPickedAt['lng']) : null;

  return AddressState(
    lat: lat,
    lng: lng,
    accuracy: _double(raw['accuracy']),
    directions: _string(raw['directions']),
    propertyName: _string(raw['propertyName']),
    propertyNumber: _string(raw['propertyNumber']),
    street: raw['street'] is String ? raw['street'] as String : null,
    unit: raw['unit'] is String ? raw['unit'] as String : null,
    neighbourhood:
        raw['neighbourhood'] is String ? raw['neighbourhood'] as String : null,
    city: raw['city'] is String ? raw['city'] as String : null,
    state: raw['state'] is String ? raw['state'] as String : null,
    postcode: raw['postcode'] is String ? raw['postcode'] as String : null,
    label: raw['label'] is String ? raw['label'] as String : null,
    parts: rawParts is Map
        ? AddressParts.fromJson(rawParts.cast<String, dynamic>())
        : null,
    pickedAt: pickedLat != null && pickedLng != null
        ? AddressPickedAt(pickedLat, pickedLng)
        : null,
    // Only a literal true restores the answered "keep". Anything else means
    // the question has not been settled, and re-asking it is the safe side.
    labelKept: raw['labelKept'] == true,
    streetView: _streetViewFromJson(raw['streetView']),
  );
}

AddressStreetView? _streetViewFromJson(Object? raw) {
  if (raw is! Map) return null;
  final panoId = raw['panoId'];
  final heading = _double(raw['heading']);
  final pitch = _double(raw['pitch']);
  final fov = _double(raw['fov']);
  // A frame is all four values or none: three of them point the camera
  // nowhere, and the server would fetch an image of somewhere else.
  if (panoId is! String || heading == null || pitch == null || fov == null) {
    return null;
  }
  return AddressStreetView(
    panoId: panoId,
    heading: heading,
    pitch: pitch,
    fov: fov,
  );
}
