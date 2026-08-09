import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business.dart';
import '../config/registration_hint.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart' show effectiveCountry;
import '../widgets/country_field.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';
import 'business_details_parts.dart';

// ─── Business (KYB) details screen ────────────────────────────────────────────
//
// The first step of a business workflow: pick the registry country (when more
// than one is offered) + product, enter the registration number (+ optional
// registered name), and fill whatever company profile the workflow asks for.
// Submits a `business` block instead of media.

class BusinessDetailsScreen extends ConsumerStatefulWidget {
  const BusinessDetailsScreen({super.key});

  @override
  ConsumerState<BusinessDetailsScreen> createState() =>
      _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState
    extends ConsumerState<BusinessDetailsScreen> {
  final _regCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _infoCtrls = {
    for (final f in CompanyInfoField.values) f: TextEditingController(),
  };
  late String _country;
  late String _product;

  WorkflowBusinessConfig get _cfg =>
      ref.read(kycConfigProvider).business ??
      WorkflowBusinessConfig(
        country: effectiveCountry(
            ref.read(kycConfigProvider), ref.read(kYCNotifierProvider)),
      );

  @override
  void initState() {
    super.initState();
    final s = ref.read(kYCNotifierProvider);
    final cfg = _cfg;
    // Precedence mirrors the web SDK exactly: the visitor's pick, then the
    // workflow's PRIMARY country. The primary is always in the offered list
    // but not necessarily FIRST — `offeredCountries.first` defaulted the
    // picker to the wrong registry whenever the primary sat later.
    _country = s.businessCountry ?? cfg.country;
    // The stored product may be from a country the user has since switched
    // away from — fall back to the first one this country actually offers.
    final offered = cfg.productsForCountry(_country);
    final stored = s.businessProduct;
    _product = (stored != null && offered.contains(stored))
        ? stored
        : offered.first;
    _regCtrl.text = s.registrationNumber ?? '';
    _nameCtrl.text = s.registrationName ?? '';
    _contactEmailCtrl.text = s.businessContactEmail ?? '';
    _infoCtrls[CompanyInfoField.address]!.text = s.businessAddress ?? '';
    _infoCtrls[CompanyInfoField.email]!.text = s.businessEmail ?? '';
    _infoCtrls[CompanyInfoField.phone]!.text = s.businessPhone ?? '';
    _infoCtrls[CompanyInfoField.website]!.text = s.businessWebsite ?? '';
  }

  @override
  void dispose() {
    _regCtrl.dispose();
    _nameCtrl.dispose();
    _contactEmailCtrl.dispose();
    for (final c in _infoCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(CompanyInfoField f) => _infoCtrls[f]!.text.trim();

  bool get _contactEmailValid {
    final value = _contactEmailCtrl.text.trim();
    return value.isEmpty || isValidContactEmail(value);
  }

  bool get _companyEmailValid {
    final value = _v(CompanyInfoField.email);
    return value.isEmpty || isValidContactEmail(value);
  }

  /// Country-aware registration-number guidance (NG: CAC prefix rules + format
  /// validation; elsewhere: placeholder + registry tip). Mirrors the web SDK.
  RegistrationHint get _regHint =>
      registrationNumberHint(_country, businessProduct(_product));

  bool get _regFormatOk {
    final check = _regHint.isValidFormat;
    final value = _regCtrl.text.trim();
    return check == null || value.isEmpty || check(value);
  }

  bool get _regNumberValid =>
      _regCtrl.text.trim().length >= 2 && _regFormatOk;

  bool get _canContinue {
    final cfg = _cfg;
    if (!_regNumberValid) return false;
    if (cfg.requireRegistrationName && _nameCtrl.text.trim().isEmpty) {
      return false;
    }
    if (!_contactEmailValid || !_companyEmailValid) return false;
    // Every `required` company-profile field must be filled.
    final modes = cfg.companyInfoModes;
    for (final f in CompanyInfoField.values) {
      if (modes[f] == CompanyInfoMode.required && _v(f).isEmpty) return false;
    }
    return true;
  }

  String? _nullIfEmpty(String value) => value.isEmpty ? null : value;

  void _onContinue() {
    if (!_canContinue) return;
    final notifier = ref.read(kYCNotifierProvider.notifier);
    notifier.setBusinessDetails(
      country: _country,
      product: _product,
      registrationNumber: _regCtrl.text.trim(),
      registrationName: _nullIfEmpty(_nameCtrl.text.trim()),
      contactEmail: _nullIfEmpty(_contactEmailCtrl.text.trim()),
      address: _nullIfEmpty(_v(CompanyInfoField.address)),
      email: _nullIfEmpty(_v(CompanyInfoField.email)),
      phone: _nullIfEmpty(_v(CompanyInfoField.phone)),
      website: _nullIfEmpty(_v(CompanyInfoField.website)),
    );
    notifier.nextStep();
  }

  /// A country switch can invalidate the picked product (the tax variants are
  /// Nigeria-only), so re-resolve it against the new country's offering.
  void _onCountryChanged(String value) {
    final offered = _cfg.productsForCountry(value);
    setState(() {
      _country = value;
      if (!offered.contains(_product)) _product = offered.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final cfg = _cfg;
    final countries = cfg.offeredCountries;
    final products = cfg.productsForCountry(_country);
    final product = businessProduct(_product);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Country of registration (when >1) ────────────────────────────────
        if (countries.length > 1) ...[
          Text('Country of registration', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          // The SAME sheet as the phone field's dial-code picker — restricted
          // to the workflow's registry countries.
          CountryField(
            country: _country,
            codes: countries,
            onChanged: _onCountryChanged,
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // ── Product (when >1 for this country) ───────────────────────────────
        if (products.length > 1) ...[
          Text('Verification type', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<String>(
            value: _product,
            sheetTitle: 'Verification type',
            options: [
              for (final p in products)
                MyazaSelectOption(value: p, label: businessProduct(p).label),
            ],
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // ── Registration number / TIN ────────────────────────────────────────
        // Placeholder + registry tip come from the country-aware hint; a wrong
        // NG CAC prefix errors live, not on Continue. Mirrors the web SDK.
        Text(product.inputLabel, style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: _regCtrl,
          hint: _regHint.placeholder,
          autofocus: true,
          // Registration numbers are uppercase codes (RC1234567, BN…) —
          // capitalize the keyboard like the RN SDK does.
          textCapitalization: TextCapitalization.characters,
          errorText: _regCtrl.text.isNotEmpty && !_regNumberValid
              ? (!_regFormatOk && _regHint.formatError != null
                  ? _regHint.formatError
                  : 'Enter a valid ${product.inputLabel.toLowerCase()}.')
              : null,
          onChanged: (_) => setState(() {}),
        ),
        if (_regHint.tip != null &&
            !(_regCtrl.text.isNotEmpty && !_regNumberValid)) ...[
          const SizedBox(height: MyazaSpacing.xs),
          Text(
            _regHint.tip!,
            style: text.bodySmall
                .copyWith(color: context.myazaColors.textSecondary),
          ),
        ],
        const SizedBox(height: MyazaSpacing.md),

        // ── Registered name (optional unless required) ───────────────────────
        BusinessFieldLabel(
          label: 'Registered business name',
          required: cfg.requireRegistrationName,
        ),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: _nameCtrl,
          hint: 'Enter the registered business name',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MyazaSpacing.md),

        // ── Company profile (workflow-configured) ────────────────────────────
        if (cfg.showsCompanyInfo)
          BusinessCompanyInfoFields(
            modes: cfg.companyInfoModes,
            controllers: _infoCtrls,
            emailValid: _companyEmailValid,
            onChanged: (_) => setState(() {}),
          ),

        // ── Key-people invite email (only when invites are emailed) ──────────
        if (cfg.needsKeyPeopleContactEmail)
          BusinessContactEmailField(
            controller: _contactEmailCtrl,
            valid: _contactEmailValid,
            onChanged: (_) => setState(() {}),
          ),

        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: 'Continue',
          onPressed: _canContinue ? _onContinue : null,
        ),
      ],
    );
  }
}
