// Opening a redo that keeps the original ID with that ID already chosen.
//
// The narrowing (step_resubmit.dart) drops the ID picker when the server
// carries the ID, so nothing in the flow would ever set one. Several things
// still read the selection: which evidence step exists (number or document),
// whether liveness runs for the ID, the chip step, and the submission's
// idType. So the kept ID is placed in state at flow start instead of asked for.
//
// Mirrors the web and RN SDKs' use of `keptIdType`. KYB is untouched: the
// server never sends an idType for a business redo.

import '../config/id_types.dart' show resolveIdTypeDefinition;
import '../config/kyc_config.dart' show MyazaKYCConfig;
import '../services/api_service.dart' show SdkConfigIdType;
import 'kyc_state.dart' show KYCState;
import 'step_order.dart' show buildStepOrder, effectiveCountry;
import 'step_resubmit.dart' show keptIdType;

/// [state] with the kept ID selected, or [state] unchanged.
///
/// Selects only when nothing is selected. The one exception is refreshing the
/// SAME key: a definition resolved before the server config arrived lacks the
/// row's scan sides and chip flag, and the applicant never chose it, so nothing
/// of theirs is overwritten.
KYCState withKeptIdType(MyazaKYCConfig config, KYCState state) {
  if (config.subjectType == 'business') return state;
  final key = keptIdType(config.resubmit);
  if (key == null) return state;
  final current = state.selectedIdType;
  if (current != null && current.key != key) return state;

  final country = effectiveCountry(config, state);
  final row = _rowFor(state, country, key);
  return state.copyWith(
    selectedIdType: resolveIdTypeDefinition(
      country,
      key,
      label: row?.label,
      requiresDocumentCapture: row?.requiresDocumentCapture,
      scanSides: row?.scanSides,
      supportsNfc: row?.supportsNfc,
    ),
  );
}

/// [withKeptIdType] for the flow's FIRST state.
///
/// The opening step was computed before any ID was chosen, and choosing one can
/// remove it: a consent-less redo that asked for the evidence opens on document
/// capture, and a number-only kept ID has no such step. Nobody has moved yet, so
/// the flow simply opens on the first step it actually has.
KYCState seedKeptIdType(MyazaKYCConfig config, KYCState initial) {
  final seeded = withKeptIdType(config, initial);
  if (identical(seeded, initial)) return initial;
  final order = buildStepOrder(config, seeded);
  return order.contains(seeded.currentStep)
      ? seeded
      : seeded.copyWith(currentStep: order.first);
}

/// The server row for the kept ID: this country's first, any country's next.
SdkConfigIdType? _rowFor(KYCState state, String country, String key) {
  SdkConfigIdType? fallback;
  for (final row in state.serverConfig.idTypes) {
    if (row.idType != key) continue;
    if (row.country.toUpperCase() == country.toUpperCase()) return row;
    fallback ??= row;
  }
  return fallback;
}
