// ─── Business (KYB) APPLICATION helpers ──────────────────────────────────────
//
// The steps a KYB workflow can add beyond the registration details: key-people
// collection, supporting documents, and applicant identity verification. Single
// source of truth for which steps are in the flow — the step order, the
// progress bar, and the submission payload all read these.
//
// Mirrors the web SDK's `lib/business-application.ts`.

import 'business.dart';

/// UI cap on applicant-entered key-people rows (the server accepts ≤20).
const int kMaxKeyPeopleRows = 10;

/// The server's hard cap on submitted key-people rows.
const int kKeyPeoplePayloadCap = 20;

// ─── Step gates ───────────────────────────────────────────────────────────────

/// Whether the flow collects key people from the applicant.
bool hasKeyPeopleCollection(WorkflowBusinessConfig? business) {
  final kp = business?.keyPeople;
  return kp != null && kp.enabled && kp.collect;
}

/// Whether the flow collects supporting business documents.
bool hasBusinessDocumentsStep(WorkflowBusinessConfig? business) =>
    business?.documents?.enabled == true;

/// Whether the applicant verifies their own identity in-flow.
bool hasApplicantVerification(WorkflowBusinessConfig? business) =>
    business?.applicant?.verification == true;

/// Minimum applicant-listed people the workflow demands (0 = skippable).
int keyPeopleMinEntries(WorkflowBusinessConfig? business) {
  if (!hasKeyPeopleCollection(business)) return 0;
  return business!.keyPeople!.minEntries;
}

/// One document slot the flow renders.
class ResolvedBusinessDocumentType {
  final String key;
  final String label;
  final bool required;

  const ResolvedBusinessDocumentType({
    required this.key,
    required this.label,
    required this.required,
  });
}

/// The document slots to render. Enabled with absent/empty `types` defaults to
/// just a required incorporation certificate (server contract).
List<ResolvedBusinessDocumentType> resolveBusinessDocumentTypes(
  WorkflowBusinessConfig? business,
) {
  if (!hasBusinessDocumentsStep(business)) return const [];
  final types = business!.documents!.types;
  if (types.isEmpty) {
    return const [
      ResolvedBusinessDocumentType(
        key: 'incorporation_certificate',
        label: 'Certificate of incorporation',
        required: true,
      ),
    ];
  }
  return types
      .map((t) => ResolvedBusinessDocumentType(
            key: t.key,
            label: t.displayLabel,
            required: t.required,
          ))
      .toList(growable: false);
}

// ─── Key-people rows ─────────────────────────────────────────────────────────

/// One row on the business-key-people step. Inputs are kept as strings for
/// controlled text fields; [keyPeoplePayload] parses and filters them.
class KeyPersonEntry {
  final String name;
  final KeyPersonRole role;
  final String email;

  /// ISO-2 country of the person (drives their verification link's country).
  final String country;

  /// Ownership percentage as typed (optional; validated 0–100 when present).
  final String ownershipPct;

  const KeyPersonEntry({
    this.name = '',
    this.role = KeyPersonRole.director,
    this.email = '',
    this.country = '',
    this.ownershipPct = '',
  });

  KeyPersonEntry copyWith({
    String? name,
    KeyPersonRole? role,
    String? email,
    String? country,
    String? ownershipPct,
  }) =>
      KeyPersonEntry(
        name: name ?? this.name,
        role: role ?? this.role,
        email: email ?? this.email,
        country: country ?? this.country,
        ownershipPct: ownershipPct ?? this.ownershipPct,
      );

  /// The typed percentage, or null when blank/unparseable.
  double? get ownershipValue {
    final raw = ownershipPct.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  /// A blank row is not an error — it is a row the user started and
  /// abandoned, and it is simply dropped. Only a row with SOMETHING in it can
  /// be invalid.
  bool get isBlank =>
      name.trim().isEmpty &&
      email.trim().isEmpty &&
      country.trim().isEmpty &&
      ownershipPct.trim().isEmpty;

  /// Row validity: name ≥2 chars; email/ownership validated only when typed.
  bool get isValid {
    if (name.trim().length < 2) return false;
    final mail = email.trim();
    if (mail.isNotEmpty && !isValidContactEmail(mail)) return false;
    final raw = ownershipPct.trim();
    if (raw.isNotEmpty) {
      final pct = double.tryParse(raw);
      if (pct == null || pct < 0 || pct > 100) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'role': role.key,
        if (email.trim().isNotEmpty) 'email': email.trim(),
        if (country.trim().isNotEmpty) 'country': country.trim().toUpperCase(),
        if (ownershipValue != null) 'ownershipPct': ownershipValue,
      };
}

/// Map valid rows into the verify payload shape (capped at the server's 20).
/// [applicantIndex] (into the UNfiltered [rows]) flags the entry the
/// applicant picked as themselves — the server merges it with the applicant
/// row so one human never becomes two KeyPerson records (one KYC, one
/// screening, no invite).
List<Map<String, dynamic>> keyPeoplePayload(
  List<KeyPersonEntry> rows, {
  int? applicantIndex,
}) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (!row.isValid) continue;
    if (out.length >= kKeyPeoplePayloadCap) break;
    out.add({
      ...row.toJson(),
      if (i == applicantIndex) 'isApplicant': true,
    });
  }
  return out;
}

/// Loose "is this the same person?" match used ONLY to PRE-SELECT the
/// applicant's own entry on the applicant-role step (from the consumer's
/// userData). Every token of the shorter name must appear in the longer one,
/// so "Richard Ingwe" matches "Richard A. Ingwe" but never "Jane Ingwe". The
/// user still confirms explicitly — this never merges anything by itself.
bool namesLooselyMatch(String a, String b) {
  List<String> tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1)
      .toList(growable: false);
  final ta = tokens(a);
  final tb = tokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  final shorter = ta.length <= tb.length ? ta : tb;
  final longer = ta.length <= tb.length ? tb : ta;
  return shorter.every(longer.contains);
}

// ─── Uploaded documents ──────────────────────────────────────────────────────

/// One uploaded slot on the business-documents step.
class BusinessDocumentUpload {
  final String type;
  final String mediaId;
  final String fileName;

  /// Local temp path of the picked image, for the slot thumbnail. Kept on the
  /// RECORD (not screen state) so the preview survives leaving and re-entering
  /// the step. Never serialized.
  final String? previewPath;
  final bool isPdf;

  const BusinessDocumentUpload({
    required this.type,
    required this.mediaId,
    required this.fileName,
    this.previewPath,
    this.isPdf = false,
  });

  Map<String, dynamic> toJson() => {'type': type, 'mediaId': mediaId};
}

// ─── Applicant ────────────────────────────────────────────────────────────────

/// Split a typed full name into first/last (best-effort) so the applicant's own
/// verification can carry a `userData` name.
({String? firstName, String? lastName})? splitFullName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(RegExp(r'\s+'));
  return (
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.sublist(1).join(' ') : null,
  );
}

/// "Richard Ingwe" → "RI" — the avatar monogram used on person cards.
String initialsOf(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((t) => t.isEmpty ? '' : t[0].toUpperCase())
    .join();
