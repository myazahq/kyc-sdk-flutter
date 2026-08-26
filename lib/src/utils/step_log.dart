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
///
/// Public because the resubmission filter (`step_resubmit.dart`) matches a
/// reviewer's chosen steps against exactly these names. Two maps would be two
/// chances to disagree about what `document-capture` is called.
const Map<KYCStep, String> kStepWireNames = {
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
  static final List<Map<String, dynamic>> _entries = [];

  /// Fresh slate per session (flow open / provider reset).
  static void reset() => _entries.clear();

  /// Records a step visit. Consecutive duplicates are collapsed; back-and-forth
  /// navigation is kept — repeat visits are honest journey data.
  /// [slot] is the 1-based multi-ID check the applicant was on, emitted only
  /// once one has been COMMITTED (on an ordinary run it would be a constant 1
  /// on every entry, which is noise).
  ///
  /// It is carried because the SERVER cannot tell a slot advance from a
  /// back-press: a multi-ID run legitimately returns to the ID picker for its
  /// next ID, and by step name alone that is identical to pressing Back. Only
  /// the client knows a check was committed, so only the client can say.
  /// [idType] is the ID selected AT THAT MOMENT. A check's final pick is not
  /// what the applicant was doing earlier in it: pick one ID, go back, settle
  /// on another, and labelling the earlier step from the committed check names
  /// an ID they had not chosen yet.
  static void record(KYCStep step, {int? slot, String? idType}) {
    if (_entries.length >= _maxEntries) return;
    final name = kStepWireNames[step] ?? step.name;
    // A revisit on a NEW check, or on a DIFFERENT ID, is a different visit.
    if (_entries.isNotEmpty &&
        _entries.last['step'] == name &&
        _entries.last['slot'] == slot &&
        _entries.last['idType'] == idType) {
      return;
    }
    _entries.add({
      'step': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      if (slot != null) 'slot': slot,
      if (idType != null) 'idType': idType,
    });
  }

  /// Snapshot attached to the verify submission. Null when nothing was
  /// recorded so the field is simply absent.
  static Map<String, dynamic>? snapshot() {
    if (_entries.isEmpty) return null;
    return {
      // NOT `List<Map<String, String>>.from(...)`. Entries carry an int `slot`,
      // so the literal above infers `Map<String, Object>` — and that cast threw
      // a TypeError on every recorded step. Because `_collectDeviceMetadata`
      // wraps its whole body in a catch that returns null, the throw discarded
      // the ENTIRE device block: no fingerprint, no SDK identity, no step log.
      // Device Intelligence read empty, the device showed as "Unknown device /
      // Unknown SDK", and the timeline had no step events — three symptoms, one
      // cast, and nothing anywhere reported an error.
      'steps': _entries.map(Map<String, dynamic>.from).toList(growable: false),
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
