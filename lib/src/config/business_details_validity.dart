import '../providers/kyc_state.dart';
import 'business.dart';
import 'website.dart';

// ─── Per-phase validity for the business-details step ────────────────────────
//
// Gated per phase: on the pick screen the detail fields do not exist yet, so
// holding Continue until they are filled would be waiting on inputs that are
// not on screen. Empty is fine (optional unless the workflow says otherwise);
// a malformed value is not. Mirrors the web SDK's isFormValid and the RN SDK's
// businessDetailsValid exactly — keep the three in lockstep.

/// [values] is keyed by the canonical business field names (the same
/// vocabulary `setBusinessField` and `registerPrefillPatch` speak).
bool businessDetailsValid({
  required String phase, // 'pick' | 'details'
  required Map<String, String> values,
  required Map<CompanyInfoField, CompanyInfoMode> modes,
  required String? product,
  required bool numberValid,
  required bool nameRequired,
  required bool showContactEmail,
}) {
  String v(String key) => (values[key] ?? '').trim();

  final pickValid = product != null &&
      product.isNotEmpty &&
      numberValid &&
      (!nameRequired || v('registrationName').isNotEmpty);
  if (phase == 'pick') return pickValid;

  final showCompanyInfo = modes.values.any((m) => m != CompanyInfoMode.off);
  final contactEmailValid =
      v('contactEmail').isEmpty || isValidContactEmail(v('contactEmail'));
  final businessEmailValid =
      v('email').isEmpty || isValidContactEmail(v('email'));
  final companyInfoComplete = modes.entries.every(
    (e) => e.value != CompanyInfoMode.required || v(e.key.key).isNotEmpty,
  );
  return pickValid &&
      (!showContactEmail || contactEmailValid) &&
      (!showCompanyInfo ||
          (businessEmailValid &&
              isValidWebsite(v('website')) &&
              companyInfoComplete));
}

/// The current business field values, in the canonical-key vocabulary the
/// validity check and the register prefill both read.
Map<String, String> businessFieldValues(KYCState s) => {
      'registrationNumber': s.registrationNumber ?? '',
      'registrationName': s.registrationName ?? '',
      'contactEmail': s.businessContactEmail ?? '',
      'address': s.businessAddress ?? '',
      'email': s.businessEmail ?? '',
      'phone': s.businessPhone ?? '',
      'website': s.businessWebsite ?? '',
      'dateOfIncorporation': s.businessDateOfIncorporation ?? '',
      'taxId': s.businessTaxId ?? '',
      'vatNumber': s.businessVatNumber ?? '',
      'companyType': s.businessCompanyType ?? '',
      'natureOfBusiness': s.businessNatureOfBusiness ?? '',
    };

/// Whether the check panel has anything to say. Found/skipped/idle stay
/// silent, and so does 'checking' — the loader lives INSIDE the Continue
/// button, since that is the thing the person just pressed.
bool checkPanelVisible(String status) =>
    status == 'not_found' || status == 'limit_reached' || status == 'unavailable';
