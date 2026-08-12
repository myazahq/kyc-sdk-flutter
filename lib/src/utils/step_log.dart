// Session step log — records each SDK step the user reaches, with a
// timestamp, so the server can reconstruct the journey on the verification
// timeline ("consent opened → ID type chosen → document captured → …").
// Rides the verify submission as metadata.device.stepLog — the same free-form
// channel the Device Intelligence fingerprint uses: no extra network calls,
// no new endpoint, and old SDKs simply never send it. `sentAt` is stamped at
// snapshot time so the server can correct client-clock skew against its own
// receipt time. Step names only — never PII. Mirrors the web SDK's
// lib/step-log.ts and the RN SDK's src/lib/step-log.ts; keep all three in
// lockstep, including the kebab-case wire names below.

import '../providers/kyc_state.dart' show KYCStep;

/// Canonical wire names shared with the web/RN SDKs — the server's timeline
/// titles key off these, so Flutter must not leak its camelCase enum names.
const Map<KYCStep, String> _wireNames = {
  KYCStep.consent: 'consent',
  KYCStep.contactEmail: 'email-verification',
  KYCStep.contactPhone: 'phone-verification',
  KYCStep.countrySelect: 'country-select',
  KYCStep.idType: 'id-type',
  KYCStep.documentCapture: 'document-capture',
  KYCStep.idInput: 'id-input',
  KYCStep.nfc: 'nfc',
  KYCStep.liveness: 'liveness',
  KYCStep.proofOfAddress: 'proof-of-address',
  KYCStep.questionnaire: 'questionnaire',
  KYCStep.businessDetails: 'business-details',
  KYCStep.businessKeyPeople: 'business-key-people',
  KYCStep.businessDocuments: 'business-documents',
  KYCStep.applicantRole: 'applicant-role',
  KYCStep.submitted: 'submitted',
};

class StepLog {
  StepLog._();

  static const int _maxEntries = 40;
  static final List<Map<String, String>> _entries = [];

  /// Fresh slate per session (flow open / provider reset).
  static void reset() => _entries.clear();

  /// Records a step visit. Consecutive duplicates are collapsed; back-and-forth
  /// navigation is kept — repeat visits are honest journey data.
  static void record(KYCStep step) {
    if (_entries.length >= _maxEntries) return;
    final name = _wireNames[step] ?? step.name;
    if (_entries.isNotEmpty && _entries.last['step'] == name) return;
    _entries.add({'step': name, 'at': DateTime.now().toUtc().toIso8601String()});
  }

  /// Snapshot attached to the verify submission. Null when nothing was
  /// recorded so the field is simply absent.
  static Map<String, dynamic>? snapshot() {
    if (_entries.isEmpty) return null;
    return {
      'steps': List<Map<String, String>>.from(_entries),
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
