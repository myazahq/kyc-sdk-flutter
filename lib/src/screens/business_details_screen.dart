import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business.dart';
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart' show effectiveCountry;
import '../widgets/country_flag.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';

// ─── Business (KYB) details screen ────────────────────────────────────────────
//
// The single input step for a business workflow: pick the registry country
// (when more than one is offered) + product, and enter the registration number
// (+ optional registered name). Submits a `business` block instead of media.

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
  late String _country;
  late String _product;

  WorkflowBusinessConfig get _cfg =>
      ref.read(kycConfigProvider).business ??
      WorkflowBusinessConfig(
        country: effectiveCountry(ref.read(kycConfigProvider), ref.read(kYCNotifierProvider)),
      );

  @override
  void initState() {
    super.initState();
    final s = ref.read(kYCNotifierProvider);
    _country = s.businessCountry ?? _cfg.offeredCountries.first;
    _product = s.businessProduct ?? _cfg.offeredProducts.first;
    _regCtrl.text = s.registrationNumber ?? '';
    _nameCtrl.text = s.registrationName ?? '';
  }

  @override
  void dispose() {
    _regCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue {
    if (_regCtrl.text.trim().isEmpty) return false;
    if (_cfg.requireRegistrationName && _nameCtrl.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  void _onContinue() {
    if (!_canContinue) return;
    final notifier = ref.read(kYCNotifierProvider.notifier);
    notifier.setBusinessDetails(
      country: _country,
      product: _product,
      registrationNumber: _regCtrl.text.trim(),
      registrationName:
          _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
    );
    notifier.nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final cfg = _cfg;
    final countries = cfg.offeredCountries;
    final products = cfg.offeredProducts;
    final product = businessProduct(_product);
    final isTin = product.input == BusinessProductInput.tin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Registry country (when >1) ───────────────────────────────────────
        if (countries.length > 1) ...[
          Text('Registry country', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<String>(
            value: _country,
            sheetTitle: 'Registry country',
            options: [
              for (final c in countries)
                MyazaSelectOption(
                  value: c,
                  label: countryLabel(c),
                  leading: MyazaCountryFlag(country: c, size: 20),
                ),
            ],
            onChanged: (v) => setState(() => _country = v),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // ── Product (when >1) ────────────────────────────────────────────────
        if (products.length > 1) ...[
          Text('Verification type', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<String>(
            value: _product,
            sheetTitle: 'Verification type',
            options: [
              for (final p in products)
                MyazaSelectOption(
                    value: p, label: businessProduct(p).label),
            ],
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // ── Registration number / TIN ────────────────────────────────────────
        Text(isTin ? 'Tax Identification Number (TIN)' : 'Registration number',
            style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: _regCtrl,
          hint: isTin ? 'Enter the business TIN' : 'e.g. RC1234567',
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MyazaSpacing.md),

        // ── Registered name (optional unless required) ───────────────────────
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Registered business name', style: text.label),
          if (!cfg.requireRegistrationName)
            TextSpan(
                text: ' (optional)',
                style: text.bodySmall
                    .copyWith(color: context.myazaColors.textSecondary)),
        ])),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: _nameCtrl,
          hint: 'As registered with the authority',
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

