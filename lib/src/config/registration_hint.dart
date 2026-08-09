import 'business.dart';
import 'id_types.dart' show countryLabel;

// ─── Registration-number guidance ─────────────────────────────────────────────
//
// Country-aware guidance for the registration-number input. Nigeria's registry
// (CAC) prefixes every number by entity type — the provider rejects a number
// whose prefix is missing or separated from the digits — so NG gets explicit
// prefix guidance AND format validation. Other registries get a placeholder +
// tip only; no format is enforced outside Nigeria.
//
// Ported from the web SDK's `lib/registration-hint.ts` — keep the two in step
// (country examples/tips are registry-verified there).

class RegistrationHint {
  final String placeholder;

  /// Guidance rendered beneath the input (null = nothing to show).
  final String? tip;

  /// Format check for the typed value (null = only non-empty is required).
  final bool Function(String value)? isValidFormat;

  /// Inline error when [isValidFormat] fails.
  final String? formatError;

  const RegistrationHint({
    required this.placeholder,
    this.tip,
    this.isValidFormat,
    this.formatError,
  });
}

final _ngPrefixRe = RegExp(r'^(RC|BN|IT|LP|LLP)\d+$', caseSensitive: false);

const _ngTip =
    'Prefix your registration number with RC for private companies limited by '
    'shares, BN for business names, IT for incorporated trustees, LP for '
    'limited partnerships or LLP for limited liability partnerships — with no '
    'space or character between the prefix and the number, e.g. RC0000000.';

/// Countries whose English name takes a definite article ("the United States").
const _theCountries = {
  'US', 'GB', 'AE', 'NL', 'PH', 'CZ', 'GM', 'BS', 'MV', 'CD', 'CF', 'DO', //
  'KM', 'MH', 'SB', 'CG',
};

String _countryName(String code) {
  final name = countryLabel(code);
  return _theCountries.contains(code.toUpperCase()) ? 'the $name' : name;
}

const _countryExamples = {
  'KE': 'PVT-JZUA6Z663',
  'ZA': '201133333323',
};

const _countryTips = {
  'KE': 'Your registration number as it appears on your certificate of '
      'incorporation, e.g. PVT-JZUA6Z663.',
  'ZA': 'Your CIPC registration number — printed as 2011/333333/23 on your '
      'documents; enter it without the slashes, e.g. 201133333323.',
};

RegistrationHint registrationNumberHint(
  String country,
  BusinessProduct product,
) {
  // TIN-keyed products keep their own placeholder/format (not a registry number).
  if (product.inputLabel == 'TIN') {
    return RegistrationHint(
      placeholder: product.placeholder,
      tip: 'Your tax identification number as issued by the tax authority, '
          'e.g. 01234567-0001.',
    );
  }

  if (country == 'NG') {
    return RegistrationHint(
      placeholder: 'e.g. RC0000000',
      tip: _ngTip,
      isValidFormat: (value) => _ngPrefixRe.hasMatch(value.trim()),
      formatError: 'Start with RC, BN, IT, LP or LLP followed by the number — '
          'no spaces, e.g. RC0000000.',
    );
  }

  final cc = country.toUpperCase();
  final example = _countryExamples[cc];
  return RegistrationHint(
    placeholder: example != null ? 'e.g. $example' : 'Enter your registration number',
    tip: _countryTips[cc] ??
        'Your official company registration number, exactly as issued by the '
            'business registry in ${_countryName(country)}.',
  );
}
