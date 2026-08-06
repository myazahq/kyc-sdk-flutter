// ─── Business (KYB) config ────────────────────────────────────────────────────
//
// A workflow can verify a BUSINESS instead of an individual (`subjectType:
// 'business'`). The flow is consent → business-details → (questionnaire) →
// submitted, and the submission carries a `business` block (registration number
// + product) instead of captured media. KYB is workflow-required server-side.
// Mirrors the web SDK's WorkflowBusinessConfig + BUSINESS_PRODUCTS.

enum BusinessProductInput { registration, tin }

/// One KYB product (a registry lookup type). `key` is the stable server value
/// carried as `idType`/`business.product`.
class BusinessProduct {
  final String key;
  final String label;
  final BusinessProductInput input;

  const BusinessProduct(this.key, this.label, this.input);
}

/// The known products. `business` is offered for every supported country; the
/// tax variants are Nigeria-only. TIN takes a TIN; the rest take a registration
/// (RC/CAC) number. Mirrors business-products.ts server-side.
const Map<String, BusinessProduct> kBusinessProducts = {
  'business':
      BusinessProduct('business', 'Business', BusinessProductInput.registration),
  'business-tax': BusinessProduct(
      'business-tax', 'Business + Tax ID', BusinessProductInput.registration),
  'business-taxid': BusinessProduct(
      'business-taxid', 'Tax ID', BusinessProductInput.registration),
  'business-tin':
      BusinessProduct('business-tin', 'TIN', BusinessProductInput.tin),
};

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

  const WorkflowBusinessConfig({
    required this.country,
    this.countries,
    this.products,
    this.requireRegistrationName = false,
  });

  /// The countries to offer (defaults to just the primary).
  List<String> get offeredCountries {
    final list = countries;
    if (list == null || list.isEmpty) return [country];
    return list;
  }

  /// The product keys to offer (defaults to `['business']`).
  List<String> get offeredProducts {
    final list = products;
    if (list == null || list.isEmpty) return const ['business'];
    return list;
  }

  factory WorkflowBusinessConfig.fromJson(Map<String, dynamic> json) =>
      WorkflowBusinessConfig(
        country: (json['country'] ?? '').toString(),
        countries: (json['countries'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false),
        products: (json['products'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false),
        requireRegistrationName:
            json['requireRegistrationName'] as bool? ?? false,
      );
}
