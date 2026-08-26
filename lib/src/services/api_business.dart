// ─── Business (KYB) API types ─────────────────────────────────────────────────
//
// The registry contract: the free name search, the paid check at selection,
// and the register's regions. Split from api_service.dart (200-line rule) and
// re-exported by it, so existing imports keep working. The server is the
// source of truth; these are declarations, never validation.

/// One officer as the register names them — the key-people prefill's input.
///
/// Everything past name and designation was simply not read before, so the
/// prefill invented nothing but also carried nothing: the ownership split the
/// register had already computed, and the email it holds for an officer, were
/// dropped on the floor and the applicant retyped both. Mirrors the RN SDK's
/// RegistryOfficer.
class RegistryOfficer {
  final String? name;
  final String? designation;

  /// Every designation the register filed this person under, when it says so.
  final List<String>? roles;

  /// The split the register computed from the share counts.
  final double? ownershipPct;

  /// An email the register holds. Registers rarely do, which is why the
  /// key-people portal exists, but when one does it saves the applicant a
  /// guess and gets that person their link sooner.
  final String? email;

  /// The register's own word on whether this party is a company. Null is NOT
  /// a denial: it is silence, and the name heuristic answers instead.
  final bool? isCorporate;
  final String? registrationNumber;

  const RegistryOfficer({
    this.name,
    this.designation,
    this.roles,
    this.ownershipPct,
    this.email,
    this.isCorporate,
    this.registrationNumber,
  });

  factory RegistryOfficer.fromJson(Map<String, dynamic> json) =>
      RegistryOfficer(
        name: json['name'] as String?,
        designation: json['designation'] as String?,
        roles: (json['roles'] as List<dynamic>?)
            ?.whereType<String>()
            .toList(growable: false),
        ownershipPct: (json['ownershipPct'] as num?)?.toDouble(),
        email: json['email'] as String?,
        isCorporate: json['isCorporate'] as bool?,
        registrationNumber: json['registrationNumber'] as String?,
      );
}

/// What the register holds about a company, when it answered. Everything is
/// nullable because no register answers all of it for every company. Mirrors
/// the RN SDK's BusinessCompanyRecord.
class BusinessCompanyRecord {
  final String? name;
  final String registrationNumber;
  final String? registrationDate;
  final String? typeOfEntity;
  final String? companyStatus;
  final String? address;
  final String? email;
  final String? phone;
  final String? taxId;
  final String? vatNumber;
  final String? natureOfBusiness;
  final String? city;
  final String? state;

  const BusinessCompanyRecord({
    this.name,
    this.registrationNumber = '',
    this.registrationDate,
    this.typeOfEntity,
    this.companyStatus,
    this.address,
    this.email,
    this.phone,
    this.taxId,
    this.vatNumber,
    this.natureOfBusiness,
    this.city,
    this.state,
  });

  factory BusinessCompanyRecord.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key]?.toString();
    return BusinessCompanyRecord(
      name: s('name'),
      registrationNumber: s('registrationNumber') ?? '',
      registrationDate: s('registrationDate'),
      typeOfEntity: s('typeOfEntity'),
      companyStatus: s('companyStatus'),
      address: s('address'),
      email: s('email'),
      phone: s('phone'),
      taxId: s('taxId'),
      vatNumber: s('vatNumber'),
      natureOfBusiness: s('natureOfBusiness'),
      city: s('city'),
      state: s('state'),
    );
  }
}

/// `POST /business/select` — the paid registry check at selection.
class BusinessSelectResponse {
  final bool checked;

  /// Why the pre-flight did not run (`checked: false`) — the submit-time
  /// lookup still happens, so this is informational, never an error.
  final String? reason;
  final bool found;

  /// What the register holds, when it answered.
  final BusinessCompanyRecord? business;
  final List<RegistryOfficer> officers;

  const BusinessSelectResponse({
    required this.checked,
    this.reason,
    required this.found,
    this.business,
    this.officers = const [],
  });

  factory BusinessSelectResponse.fromJson(Map<String, dynamic> json) {
    final business = json['business'];
    final people = business is Map ? business['keyPeople'] : null;
    return BusinessSelectResponse(
      checked: json['checked'] == true,
      reason: json['reason']?.toString(),
      found: json['found'] == true,
      business: business is Map
          ? BusinessCompanyRecord.fromJson(business.cast<String, dynamic>())
          : null,
      officers: people is List
          ? people
              .whereType<Map>()
              .map((e) => RegistryOfficer.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// One candidate from the FREE name search — picking one is what leads to the
/// paid register check.
class BusinessSearchHit {
  final String name;
  final String registrationNumber;
  final String? status;

  const BusinessSearchHit({
    required this.name,
    required this.registrationNumber,
    this.status,
  });

  factory BusinessSearchHit.fromJson(Map<String, dynamic> json) =>
      BusinessSearchHit(
        name: (json['name'] ?? '').toString(),
        registrationNumber: (json['registrationNumber'] ?? '').toString(),
        status: json['status']?.toString(),
      );
}

/// `GET /business/search` — find a business by name.
class BusinessSearchResponse {
  final List<BusinessSearchHit> results;

  /// Which source answered; a degraded fallback names itself here.
  final String source;

  const BusinessSearchResponse({required this.results, this.source = ''});

  factory BusinessSearchResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    return BusinessSearchResponse(
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => BusinessSearchHit.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
      source: (json['source'] ?? '').toString(),
    );
  }
}

/// One registry region of a split register (US states, IN states, CA
/// provinces, AE emirates).
class BusinessRegion {
  final String code;
  final String name;

  const BusinessRegion({required this.code, required this.name});

  factory BusinessRegion.fromJson(Map<String, dynamic> json) => BusinessRegion(
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );
}

/// `GET /business/regions` — the registry regions of a split register. Empty
/// for a country with a single register.
class BusinessRegionsResponse {
  final List<BusinessRegion> regions;

  const BusinessRegionsResponse({this.regions = const []});

  factory BusinessRegionsResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['regions'];
    return BusinessRegionsResponse(
      regions: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => BusinessRegion.fromJson(e.cast<String, dynamic>()))
              .where((r) => r.code.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}
