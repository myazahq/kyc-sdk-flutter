// ─── Business (KYB) config ────────────────────────────────────────────────────
//
// A workflow can verify a BUSINESS instead of an individual (`subjectType:
// 'business'`). The core flow is consent → business-details → (questionnaire) →
// submitted, and the submission carries a `business` block (registration number
// + product) instead of captured media. KYB is workflow-required server-side.
//
// A workflow can additionally request an APPLICATION section — company profile,
// directors/owners, supporting documents, and the applicant's own identity
// verification. Those gates live in `business_application.dart`; this file holds
// the config models and the product catalog.
//
// Mirrors the web SDK's `types/business.ts` + `lib/business.ts`.

enum BusinessProductInput { registration, tin }

/// One KYB product (a registry lookup type). `key` is the stable server value
/// carried as `idType`/`business.product`.
class BusinessProduct {
  final String key;
  final String label;
  final BusinessProductInput input;

  /// Countries offering this product; empty = every supported country.
  final List<String> countries;

  const BusinessProduct(
    this.key,
    this.label,
    this.input, {
    this.countries = const [],
  });

  /// What the user types — drives the input label + placeholder.
  String get inputLabel => input == BusinessProductInput.tin
      ? 'Tax Identification Number (TIN)'
      : 'Registration number';

  String get placeholder =>
      input == BusinessProductInput.tin ? 'e.g. 01234567-0001' : 'e.g. RC0000000';

  bool availableIn(String country) =>
      countries.isEmpty || countries.contains(country.toUpperCase());
}

/// The known products. `business` is offered for every supported country; the
/// tax variants are Nigeria-only. TIN takes a TIN; the rest take a registration
/// (RC/CAC) number. Mirrors business-products.ts server-side.
const Map<String, BusinessProduct> kBusinessProducts = {
  'business':
      BusinessProduct('business', 'Business', BusinessProductInput.registration),
  'business-tax': BusinessProduct(
      'business-tax', 'Business + Tax ID', BusinessProductInput.registration,
      countries: ['NG']),
  'business-taxid': BusinessProduct(
      'business-taxid', 'Tax ID', BusinessProductInput.registration,
      countries: ['NG']),
  'business-tin': BusinessProduct(
      'business-tin', 'TIN', BusinessProductInput.tin,
      countries: ['NG']),
};

const String kDefaultBusinessProduct = 'business';

/// Resolves a product key to its definition (falling back to a humanized label
/// for an unknown key so the picker still renders).
BusinessProduct businessProduct(String key) =>
    kBusinessProducts[key] ??
    BusinessProduct(key, _humanize(key), BusinessProductInput.registration);

String _humanize(String key) => key
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Format-only email check, used for the optional contact/company emails and
/// key-person rows (validated only when non-empty).
bool isValidContactEmail(String value) =>
    value.length <= 254 &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

// ─── Company profile ──────────────────────────────────────────────────────────

/// The company-profile fields a workflow can collect on the business-details
/// step. The address is cross-checked against the registry record server-side.
/// The last five are registry facts the applicant STATES: asked as their own
/// answer rather than filled from the register, because where the two differ
/// that is the finding. Mirrors the web SDK's CompanyInfoField exactly.
enum CompanyInfoField {
  address,
  email,
  phone,
  website,
  dateOfIncorporation,
  taxId,
  vatNumber,
  companyType,
  natureOfBusiness,
}

/// Per-field collection mode. `off` hides it, `required` blocks Continue.
enum CompanyInfoMode { off, optional, required }

CompanyInfoMode _companyInfoMode(String? raw) => switch (raw) {
      'off' => CompanyInfoMode.off,
      'required' => CompanyInfoMode.required,
      _ => CompanyInfoMode.optional,
    };

extension CompanyInfoFieldX on CompanyInfoField {
  String get key => name;

  String get label => switch (this) {
        CompanyInfoField.address => 'Registered address',
        CompanyInfoField.email => 'Business email',
        CompanyInfoField.phone => 'Business phone',
        CompanyInfoField.website => 'Website',
        CompanyInfoField.dateOfIncorporation => 'Date of incorporation',
        CompanyInfoField.taxId => 'Tax ID',
        CompanyInfoField.vatNumber => 'VAT number',
        CompanyInfoField.companyType => 'Company type',
        CompanyInfoField.natureOfBusiness => 'Nature of business',
      };

  String get placeholder => switch (this) {
        CompanyInfoField.address => 'e.g. 12 Marina Road, Lagos',
        CompanyInfoField.email => 'hello@company.com',
        CompanyInfoField.phone => '+234 800 000 0000',
        CompanyInfoField.website => 'company.com',
        CompanyInfoField.dateOfIncorporation => 'YYYY-MM-DD',
        CompanyInfoField.taxId => 'e.g. 01234567-0001',
        CompanyInfoField.vatNumber => 'e.g. NG123456789',
        CompanyInfoField.companyType => 'e.g. Private Limited Company',
        CompanyInfoField.natureOfBusiness => 'What the company does',
      };
}

// ─── Key people (directors / owners) ─────────────────────────────────────────

/// Associated-party roles discovered from the registry lookup or declared by
/// the applicant.
enum KeyPersonRole { director, beneficialOwner, signatory, shareholder }

/// Roles the APPLICANT (the person submitting) may declare — the key-person
/// roles plus someone filing on the company's behalf.
enum ApplicantRole {
  director,
  beneficialOwner,
  signatory,
  shareholder,
  authorizedRepresentative,
}

extension KeyPersonRoleX on KeyPersonRole {
  /// The stable server value (snake_case).
  String get key => switch (this) {
        KeyPersonRole.director => 'director',
        KeyPersonRole.beneficialOwner => 'beneficial_owner',
        KeyPersonRole.signatory => 'signatory',
        KeyPersonRole.shareholder => 'shareholder',
      };

  String get label => switch (this) {
        KeyPersonRole.director => 'Director',
        KeyPersonRole.beneficialOwner => 'Beneficial owner (UBO)',
        KeyPersonRole.signatory => 'Signatory',
        KeyPersonRole.shareholder => 'Shareholder',
      };

  /// Whether an ownership percentage is meaningful for this role.
  bool get isOwnerRole =>
      this == KeyPersonRole.beneficialOwner || this == KeyPersonRole.shareholder;
}

extension ApplicantRoleX on ApplicantRole {
  String get key => switch (this) {
        ApplicantRole.director => 'director',
        ApplicantRole.beneficialOwner => 'beneficial_owner',
        ApplicantRole.signatory => 'signatory',
        ApplicantRole.shareholder => 'shareholder',
        ApplicantRole.authorizedRepresentative => 'authorized_representative',
      };

  String get label => switch (this) {
        ApplicantRole.director => 'Director',
        ApplicantRole.beneficialOwner => 'Beneficial owner (UBO)',
        ApplicantRole.signatory => 'Signatory',
        ApplicantRole.shareholder => 'Shareholder',
        ApplicantRole.authorizedRepresentative => 'Authorized representative',
      };
}

KeyPersonRole? keyPersonRoleFromKey(String key) {
  for (final role in KeyPersonRole.values) {
    if (role.key == key) return role;
  }
  return null;
}

/// Verification depth for a discovered/declared key person.
enum KeyPeopleLevel { screeningOnly, data, fullKyc }

KeyPeopleLevel _levelFromKey(String? key) => switch (key) {
      'data' => KeyPeopleLevel.data,
      'full_kyc' => KeyPeopleLevel.fullKyc,
      _ => KeyPeopleLevel.screeningOnly,
    };

/// Key-people (associated-party) verification block on a KYB workflow. The SDK
/// only reads the collection gate + the email-invite gate; the rest is server
/// policy carried along for completeness.
class WorkflowKeyPeopleConfig {
  final bool enabled;

  /// The SDK collects directors/owners from the applicant (adds the
  /// business-key-people step).
  final bool collect;

  /// Minimum people the applicant must list when [collect] is on (0 = skippable).
  final int minEntries;

  /// Ownership % at/above which the server escalates a person to beneficial
  /// owner (the workflow's `keyPeople.ownershipThreshold`).
  ///
  /// NULLABLE, because the default is PER REGISTER and this class does not know
  /// the country: the server's `uboThresholdFor` uses 25 globally but 10 for
  /// Nigeria, whose CAMA files significant control from a lower bar. Defaulted
  /// to 25 here, an NG flow classified at 25 on screen while the submission was
  /// read at 10, and the two disagreed about who was a beneficial owner.
  /// Resolve with [defaultUboThreshold], never with a literal.
  final double? ownershipThreshold;

  /// In-scope roles. Empty = all four.
  final List<KeyPersonRole> roles;

  /// Default verification depth when a role has no [perRole] override.
  final KeyPeopleLevel? level;

  /// Per-role verification depth overrides (win over [level]).
  final Map<KeyPersonRole, KeyPeopleLevel> perRole;

  /// Invite distribution channel for full-KYC people (e.g. `email`).
  final String? inviteChannel;

  /// Emails are mandatory for the roles that are sent a verification link.
  final bool requireEmail;

  /// Explicit override of WHICH roles must carry an email.
  final List<KeyPersonRole> requireEmailRoles;

  const WorkflowKeyPeopleConfig({
    this.enabled = false,
    this.collect = false,
    this.minEntries = 0,
    this.ownershipThreshold,
    this.roles = const [],
    this.corporateKyb = false,
    this.level,
    this.perRole = const {},
    this.inviteChannel,
    this.requireEmail = false,
    this.requireEmailRoles = const [],
  });

  /// Nested KYB: a corporate shareholder is invited into its OWN business
  /// application rather than merely screened. Changes what the applicant is
  /// told about a company they list — with it on the company receives a link
  /// and its owners are identified there; without it the company is screened
  /// and its owners reviewed separately.
  final bool corporateKyb;

  /// The roles actually in scope (all four when unset).
  List<KeyPersonRole> get scopedRoles =>
      roles.isEmpty ? KeyPersonRole.values : roles;

  /// The resolved verification depth for [role] — mirrors the server's
  /// `perRole[role] ?? level ?? screening_only`.
  KeyPeopleLevel levelFor(KeyPersonRole role) =>
      perRole[role] ?? level ?? KeyPeopleLevel.screeningOnly;

  factory WorkflowKeyPeopleConfig.fromJson(Map<String, dynamic> json) {
    final rawPerRole = json['perRole'];
    final perRole = <KeyPersonRole, KeyPeopleLevel>{};
    if (rawPerRole is Map) {
      rawPerRole.forEach((k, v) {
        final role = keyPersonRoleFromKey(k.toString());
        if (role != null) perRole[role] = _levelFromKey(v?.toString());
      });
    }
    final rawRoles = json['roles'];
    List<KeyPersonRole> roleList(dynamic raw) => raw is List
        ? raw
            .map((e) => keyPersonRoleFromKey(e.toString()))
            .whereType<KeyPersonRole>()
            .toList(growable: false)
        : const [];
    return WorkflowKeyPeopleConfig(
      enabled: json['enabled'] as bool? ?? false,
      collect: json['collect'] as bool? ?? false,
      minEntries: (json['minEntries'] as num?)?.toInt() ?? 0,
      ownershipThreshold: (json['ownershipThreshold'] as num?)?.toDouble(),
      roles: roleList(rawRoles),
      // `{ enabled, workflowId }` — only the switch matters to the SDK; WHICH
      // workflow the company is sent to is the server's business.
      corporateKyb: (json['corporateKyb'] is Map) &&
          ((json['corporateKyb'] as Map)['enabled'] as bool? ?? false),
      level: json['level'] != null ? _levelFromKey(json['level'].toString()) : null,
      perRole: perRole,
      inviteChannel: (json['invite'] is Map)
          ? (json['invite'] as Map)['channel']?.toString()
          : null,
      requireEmail: json['requireEmail'] as bool? ?? false,
      requireEmailRoles: roleList(json['requireEmailRoles']),
    );
  }
}

// ─── Supporting documents ─────────────────────────────────────────────────────

/// Default display labels per document key (server contract). Unknown keys fall
/// back to a humanized label so a new server type still renders.
const Map<String, String> kBusinessDocumentLabels = {
  'incorporation_certificate': 'Certificate of incorporation',
  'memart': 'MEMART / articles of association',
  'proof_of_address': 'Proof of business address',
  'tax_document': 'Tax document',
  'regulatory_license': 'Regulatory license',
  'board_resolution': 'Board resolution',
  'other': 'Other document',
};

String businessDocumentLabel(String key) =>
    kBusinessDocumentLabels[key] ?? _humanize(key);

/// One requested document slot on a KYB workflow's `documents` block.
class WorkflowBusinessDocumentType {
  final String key;

  /// Display label override (defaults per key).
  final String? label;

  /// Submission is blocked (422 `missing_documents`) until this slot is filled.
  final bool required;

  const WorkflowBusinessDocumentType({
    required this.key,
    this.label,
    this.required = false,
  });

  String get displayLabel => label ?? businessDocumentLabel(key);

  factory WorkflowBusinessDocumentType.fromJson(Map<String, dynamic> json) =>
      WorkflowBusinessDocumentType(
        key: (json['key'] ?? '').toString(),
        label: json['label']?.toString(),
        required: json['required'] as bool? ?? false,
      );
}

/// Supporting-document collection block. `enabled` with absent/empty `types`
/// defaults to just a required incorporation certificate (server contract).
class WorkflowBusinessDocumentsConfig {
  final bool enabled;
  final List<WorkflowBusinessDocumentType> types;

  const WorkflowBusinessDocumentsConfig({
    this.enabled = false,
    this.types = const [],
  });

  factory WorkflowBusinessDocumentsConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['types'];
    return WorkflowBusinessDocumentsConfig(
      enabled: json['enabled'] as bool? ?? false,
      types: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => WorkflowBusinessDocumentType.fromJson(
                  e.cast<String, dynamic>()))
              .where((t) => t.key.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}

/// Applicant-verification block: when `verification` is true the applicant
/// verifies their OWN identity in-flow (role declaration + the ordinary
/// individual capture steps), linked back via `metadata.userId`.
class WorkflowBusinessApplicantConfig {
  final bool verification;

  const WorkflowBusinessApplicantConfig({this.verification = false});

  factory WorkflowBusinessApplicantConfig.fromJson(Map<String, dynamic> json) =>
      WorkflowBusinessApplicantConfig(
        verification: json['verification'] as bool? ?? false,
      );
}

// ─── The workflow's business block ───────────────────────────────────────────

class WorkflowBusinessConfig {
  /// Primary/default registry country (ISO-2). KYB supports ~48 provider
  /// countries — a free string, not the individual 5-country set.
  final String country;

  /// Multi-registry list the visitor picks from (absent/single = just [country]).
  final List<String>? countries;

  /// Offered product keys (absent/empty = `['business']`).
  final List<String>? products;

  /// Whether the registered name field is required (else optional).
  final bool requireRegistrationName;

  /// Collect the company profile on the business-details step. Default ON;
  /// false hides the whole section.
  final bool collectCompanyInfo;

  /// Per-field company-profile modes (absent field = optional).
  final Map<CompanyInfoField, CompanyInfoMode> companyInfo;

  /// Directors/owners collection + verification.
  final WorkflowKeyPeopleConfig? keyPeople;

  /// Supporting-document collection.
  final WorkflowBusinessDocumentsConfig? documents;

  /// Applicant (submitter) identity verification.
  final WorkflowBusinessApplicantConfig? applicant;

  const WorkflowBusinessConfig({
    required this.country,
    this.countries,
    this.products,
    this.requireRegistrationName = false,
    this.collectCompanyInfo = true,
    this.companyInfo = const {},
    this.keyPeople,
    this.documents,
    this.applicant,
  });

  /// The countries to offer (defaults to just the primary; the primary is
  /// always included and leads).
  List<String> get offeredCountries {
    final list = countries;
    if (list == null || list.isEmpty) return [country];
    return list.contains(country) ? list : [country, ...list];
  }

  /// The product keys to offer (defaults to `['business']`).
  List<String> get offeredProducts {
    final list = products;
    if (list == null || list.isEmpty) return const [kDefaultBusinessProduct];
    return list;
  }

  /// The products offered for one picked country — the configured list narrowed
  /// by each product's country availability, with the default product as the
  /// backstop. Mirrors the server's `businessProductsForCountry`.
  List<String> productsForCountry(String pickedCountry) {
    final offered = offeredProducts
        .where((key) => businessProduct(key).availableIn(pickedCountry))
        .toList(growable: false);
    return offered.isEmpty ? const [kDefaultBusinessProduct] : offered;
  }

  /// Effective per-field company-profile mode: `collectCompanyInfo: false` ⇒
  /// everything off; an absent field is optional. Mirrors the server exactly.
  Map<CompanyInfoField, CompanyInfoMode> get companyInfoModes => {
        for (final f in CompanyInfoField.values)
          f: collectCompanyInfo
              ? (companyInfo[f] ?? CompanyInfoMode.optional)
              : CompanyInfoMode.off,
      };

  /// Whether any company-profile field is visible.
  bool get showsCompanyInfo =>
      companyInfoModes.values.any((m) => m != CompanyInfoMode.off);

  /// Whether the business-details step should collect a contact email for
  /// key-people invites: the block is enabled, invites go out by email, and at
  /// least one in-scope role resolves to full KYC. Mirrors the server.
  bool get needsKeyPeopleContactEmail {
    final kp = keyPeople;
    if (kp == null || !kp.enabled || kp.inviteChannel != 'email') return false;
    return kp.scopedRoles
        .any((role) => kp.levelFor(role) == KeyPeopleLevel.fullKyc);
  }

  factory WorkflowBusinessConfig.fromJson(Map<String, dynamic> json) {
    final rawInfo = json['companyInfo'];
    final companyInfo = <CompanyInfoField, CompanyInfoMode>{};
    if (rawInfo is Map) {
      for (final field in CompanyInfoField.values) {
        final raw = rawInfo[field.key];
        if (raw != null) companyInfo[field] = _companyInfoMode(raw.toString());
      }
    }
    Map<String, dynamic>? sub(String key) {
      final raw = json[key];
      return raw is Map ? raw.cast<String, dynamic>() : null;
    }

    final keyPeople = sub('keyPeople');
    final documents = sub('documents');
    final applicant = sub('applicant');

    return WorkflowBusinessConfig(
      country: (json['country'] ?? '').toString(),
      countries: (json['countries'] as List?)
          ?.map((e) => e.toString())
          .toList(growable: false),
      products: (json['products'] as List?)
          ?.map((e) => e.toString())
          .toList(growable: false),
      requireRegistrationName: json['requireRegistrationName'] as bool? ?? false,
      collectCompanyInfo: json['collectCompanyInfo'] as bool? ?? true,
      companyInfo: companyInfo,
      keyPeople:
          keyPeople != null ? WorkflowKeyPeopleConfig.fromJson(keyPeople) : null,
      documents: documents != null
          ? WorkflowBusinessDocumentsConfig.fromJson(documents)
          : null,
      applicant: applicant != null
          ? WorkflowBusinessApplicantConfig.fromJson(applicant)
          : null,
    );
  }
}
