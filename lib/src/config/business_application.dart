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

  /// This party is a company, not a person.
  ///
  /// A company can never be a beneficial owner, so it is screened as an entity
  /// and never asked to verify an identity it does not have. Saying so is what
  /// stops the flow sending a document-and-selfie link to a limited company and
  /// then waiting for it.
  final bool isCorporate;

  /// A corporate party's own registration number, as typed.
  final String registrationNumber;

  /// The people who own a corporate party, as the applicant knows them. The
  /// only route to the humans above a parent no register we serve can be asked
  /// about: a foreign holding company, an offshore vehicle.
  final List<KeyPersonOwnerEntry> owners;

  /// The human nuance the closed role vocabulary cannot carry: "CFO", "Board
  /// Member". Display-only, and deliberately separate from [roles] because
  /// classification drives who gets screened and invited, while a job title
  /// drives nothing. The server keeps it on `KeyPerson.title`.
  final String title;

  /// EVERY hat this party wears, because one human routinely wears several:
  /// a director who also holds 30% is filed by the register as both, and the
  /// server takes a set of 1-4 for exactly that reason.
  ///
  /// [role] stays the HEADLINE (strongest by precedence) because every
  /// one-role surface reads it. Empty means "only the headline is known",
  /// which is what a row restored from an older session carries.
  final List<KeyPersonRole> roles;

  const KeyPersonEntry({
    this.name = '',
    this.role = KeyPersonRole.director,
    this.roles = const [],
    this.title = '',
    this.email = '',
    this.country = '',
    this.ownershipPct = '',
    this.isCorporate = false,
    this.registrationNumber = '',
    this.owners = const [],
  });

  KeyPersonEntry copyWith({
    String? name,
    KeyPersonRole? role,
    List<KeyPersonRole>? roles,
    String? title,
    String? email,
    String? country,
    String? ownershipPct,
    bool? isCorporate,
    String? registrationNumber,
    List<KeyPersonOwnerEntry>? owners,
  }) =>
      KeyPersonEntry(
        name: name ?? this.name,
        role: role ?? this.role,
        roles: roles ?? this.roles,
        title: title ?? this.title,
        email: email ?? this.email,
        country: country ?? this.country,
        ownershipPct: ownershipPct ?? this.ownershipPct,
        isCorporate: isCorporate ?? this.isCorporate,
        registrationNumber: registrationNumber ?? this.registrationNumber,
        owners: owners ?? this.owners,
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
  bool get isValid => isValidWith(const {});

  /// Row validity against the roles whose email is MANDATORY (they are sent a
  /// verification link — see [keyPeopleRequireEmail]).
  ///
  /// The server enforces the required email too, but only at SUBMIT — several
  /// steps later, as a generic failure, with no way back to the row that is
  /// missing one. Blocking here is where the person can still fix it.
  bool isValidWith(Set<KeyPersonRole> emailRequiredFor) {
    if (name.trim().length < 2) return false;
    if (rowNeedsEmail(this, emailRequiredFor) && email.trim().isEmpty) {
      return false;
    }
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
        // Sent only when it carries more than the headline: the server accepts
        // either, and an unchanged single-role row should serialise exactly as
        // it did before this existed.
        if (roles.length > 1) 'roles': roles.map((r) => r.key).toList(),
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (email.trim().isNotEmpty) 'email': email.trim(),
        if (country.trim().isNotEmpty) 'country': country.trim().toUpperCase(),
        if (ownershipValue != null) 'ownershipPct': ownershipValue,
        if (isCorporate) 'isCorporate': true,
        if (isCorporate && registrationNumber.trim().isNotEmpty)
          'registrationNumber': registrationNumber.trim(),
        if (isCorporate && _validOwners.isNotEmpty)
          'owners': _validOwners.map((o) => o.toJson()).toList(),
      };

  /// Named owners only, capped at the server's ten. A half-typed row is a row
  /// the applicant abandoned, not a person they disclosed.
  List<KeyPersonOwnerEntry> get _validOwners =>
      owners.where((o) => o.name.trim().length >= 2).take(10).toList();
}

/// One declared owner of a corporate key person.
class KeyPersonOwnerEntry {
  final String name;

  /// Their share OF THE COMPANY above. The server multiplies it down the chain.
  final String ownershipPct;
  final String email;
  final String country;

  const KeyPersonOwnerEntry({
    this.name = '',
    this.ownershipPct = '',
    this.email = '',
    this.country = '',
  });

  KeyPersonOwnerEntry copyWith({
    String? name,
    String? ownershipPct,
    String? email,
    String? country,
  }) =>
      KeyPersonOwnerEntry(
        name: name ?? this.name,
        ownershipPct: ownershipPct ?? this.ownershipPct,
        email: email ?? this.email,
        country: country ?? this.country,
      );

  double? get ownershipValue {
    final raw = ownershipPct.trim();
    if (raw.isEmpty) return null;
    final pct = double.tryParse(raw);
    return pct != null && pct >= 0 && pct <= 100 ? pct : null;
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        if (ownershipValue != null) 'ownershipPct': ownershipValue,
        if (email.trim().isNotEmpty) 'email': email.trim(),
        if (country.trim().isNotEmpty) 'country': country.trim().toUpperCase(),
      };
}

/// The roles whose EMAIL is mandatory: the ones that are actually sent a
/// verification link. Asking a screening-only signatory for an address blocks
/// the form over a field nothing will read. Empty unless the workflow collects
/// key people AND sets `requireEmail`; then `requireEmailRoles` when non-empty,
/// else the roles whose resolved level is full KYC. Mirrors the web SDK's
/// keyPeopleRequireEmail — keep the two in lockstep.
Set<KeyPersonRole> keyPeopleRequireEmail(WorkflowBusinessConfig? business) {
  final kp = business?.keyPeople;
  if (kp == null || !kp.enabled || !kp.collect || !kp.requireEmail) return {};
  if (kp.requireEmailRoles.isNotEmpty) return kp.requireEmailRoles.toSet();
  return KeyPersonRole.values
      .where((role) => kp.levelFor(role) == KeyPeopleLevel.fullKyc)
      .toSet();
}

/// Whether THIS row must carry an email. A company has no inbox and is never
/// invited, so a corporate row is always exempt.
bool rowNeedsEmail(KeyPersonEntry row, Set<KeyPersonRole> emailRequiredFor) =>
    !row.isCorporate && emailRequiredFor.contains(row.role);

/// Corporate designators, matched only at the END of a name.
///
/// End-anchored on purpose: "Trust", "Grace" and "Precious" are ordinary
/// Nigerian given names, and nobody is called "X Limited".
const _corporateSuffixes = {
  'limited', 'ltd', 'plc', 'inc', 'incorporated', 'llc', 'llp', 'gmbh', 'nv',
  'bv', 'pty', 'corporation', 'corp', 'nominees', 'holdings', 'trustees',
  'ventures', 'enterprises',
};

/// Whether a registry name reads as a company.
bool looksCorporate(String name) {
  final parts = name
      .toLowerCase()
      .replaceAll(RegExp(r'[.,()]'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  return parts.isNotEmpty && _corporateSuffixes.contains(parts.last);
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
    // A company cannot also be the person filling in the form, so the
    // applicant's own entry is never sent as one.
    final json = row.toJson();
    if (i == applicantIndex) {
      json.remove('isCorporate');
      json.remove('owners');
      json['isApplicant'] = true;
    }
    out.add(json);
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
