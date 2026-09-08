import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business.dart';
import '../config/business_details_validity.dart';
import '../config/business_prefill.dart';
import '../config/registration_hint.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../providers/step_order.dart' show effectiveCountry;
import '../widgets/country_field.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_select.dart';
import 'business_check_panel.dart';
import 'business_details_fields.dart';
import 'business_picked_section.dart';
import 'business_search.dart';

// ─── Business (KYB) registry details — two screens in one step ────────────────
//
// 'pick' is choosing WHICH company. 'details' is confirming what the register
// then said about it. They are separate because the register has not been
// asked yet while you are still picking, so showing the detail fields there
// would invite somebody to fill in answers we are about to overwrite.
// Continue is what runs the paid check and moves between them. Mirrors the
// web and RN SDKs' BusinessDetailsStep — keep the three in lockstep.

class BusinessDetailsScreen extends ConsumerStatefulWidget {
  const BusinessDetailsScreen({super.key});

  @override
  ConsumerState<BusinessDetailsScreen> createState() =>
      _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends ConsumerState<BusinessDetailsScreen> {
  String _phase = 'pick'; // 'pick' | 'details'
  final _regCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _infoCtrls = {
    for (final f in CompanyInfoField.values) f: TextEditingController(),
  };

  WorkflowBusinessConfig get _cfg =>
      ref.read(kycConfigProvider).business ??
      WorkflowBusinessConfig(
        country: effectiveCountry(
            ref.read(kycConfigProvider), ref.read(kYCNotifierProvider)),
      );

  @override
  void initState() {
    super.initState();
    _syncFromState();
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

  /// State is the source of truth (every keystroke writes through), so the
  /// controllers only ever need catching up when something ELSE moved it: a
  /// register prefill landing, or a company change clearing the fields the
  /// old register filled.
  void _syncFromState() {
    final values = businessFieldValues(ref.read(kYCNotifierProvider));
    void sync(TextEditingController ctrl, String value) {
      if (ctrl.text != value) ctrl.text = value;
    }

    sync(_regCtrl, values['registrationNumber']!);
    sync(_nameCtrl, values['registrationName']!);
    sync(_contactEmailCtrl, values['contactEmail']!);
    for (final f in CompanyInfoField.values) {
      sync(_infoCtrls[f]!, values[f.key]!);
    }
  }

  void _set(String key, String value) {
    ref.read(kYCNotifierProvider.notifier).setBusinessField(key, value);
    // An identity-key change clears the register-filled fields in state; the
    // controllers holding those values must follow.
    _syncFromState();
    setState(() {});
  }

  Future<void> _onContinue() async {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    // The paid registry check — awaited, so the details screen opens already
    // holding what the register said. Only a definitive "not on the register"
    // stops the flow: everything else (a short balance, an outage) continues
    // and is checked at submission, as it was before.
    final result = await notifier.checkBusiness();
    if (!mounted) return;
    if (!result.canContinue) {
      setState(() {});
      return;
    }
    // First Continue ends at the details screen rather than the next step: the
    // register has only just answered, and this is where what it said gets put
    // in front of them to confirm or correct.
    if (_phase == 'pick') {
      final current = businessFieldValues(ref.read(kYCNotifierProvider));
      final prefill = registerPrefillPatch(result.company, current);
      if (prefill.prefilled.isNotEmpty) {
        notifier.applyBusinessPrefill(prefill.patch, prefill.prefilled);
      }
      _syncFromState();
      setState(() => _phase = 'details');
      return;
    }
    notifier.nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final s = ref.watch(kYCNotifierProvider);
    final cfg = _cfg;
    final countries = cfg.offeredCountries;
    // Precedence mirrors the web SDK: the visitor's pick, then the workflow's
    // PRIMARY country (always in the offered list but not necessarily first).
    final country = s.businessCountry ?? cfg.country;
    final products = cfg.productsForCountry(country);
    final stored = s.businessProduct;
    // Re-derived per country rather than remembered: a product the picked
    // country does not offer would be rejected at submit.
    final product = (stored != null && products.contains(stored))
        ? stored
        : products.first;
    final productDef = businessProduct(product);
    final regHint = registrationNumberHint(country, productDef);

    final modes = cfg.companyInfoModes;
    final showCompanyInfo = cfg.showsCompanyInfo;
    final showContactEmail = cfg.needsKeyPeopleContactEmail;

    final regNumber = (s.registrationNumber ?? '').trim();
    // A company has been named, so the card replaces the search. The NUMBER is
    // what names it (a prefilled session sends one without a name; the
    // register supplies the name on Continue, so an unnamed card is momentary).
    final picked = regNumber.isNotEmpty;
    final formatCheck = regHint.isValidFormat;
    final formatOk =
        formatCheck == null || regNumber.isEmpty || formatCheck(regNumber);
    final numberValid = regNumber.length >= 2 && formatOk;

    final isFormValid = businessDetailsValid(
      phase: _phase,
      values: businessFieldValues(s),
      modes: modes,
      product: product,
      numberValid: numberValid,
      nameRequired: cfg.requireRegistrationName,
      showContactEmail: showContactEmail,
    );
    final checking = s.businessCheck.status == 'checking';
    // Production never shows the test-result toggle, and never honours a pin.
    final isSandbox = s.serverConfig.environment != 'PRODUCTION';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (countries.length > 1) ...[
          Text('Country of registration', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          CountryField(
            country: country,
            codes: countries,
            onChanged: (code) {
              _set('country', code);
              // The product list narrows per country, so a stale pick is
              // cleared rather than carried into a refused submission.
              _set('product', '');
            },
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],
        if (products.length > 1) ...[
          Text('Verification type', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<String>(
            value: product,
            sheetTitle: 'Verification type',
            options: [
              for (final p in products)
                MyazaSelectOption(value: p, label: businessProduct(p).label),
            ],
            onChanged: (v) => _set('product', v),
          ),
          const SizedBox(height: MyazaSpacing.md),
        ],

        // HIDDEN, not unmounted, once a company is chosen: unmounting threw
        // away the query and results, so "Change" dropped somebody back to an
        // empty box. Hiding keeps the picker alive, which makes Change cheap.
        Offstage(
          offstage: !(_phase == 'pick' && country.isNotEmpty && !picked),
          child: BusinessSearch(
            country: country,
            onPicked: (hit) {
              // Names the company and nothing more: the register is asked on
              // Continue, and the fields it fills live on the screen after.
              _set('registrationNumber', hit.registrationNumber);
              _set('registrationName', hit.name);
            },
            onManualEntry: () => setState(() => _phase = 'details'),
          ),
        ),

        if (_phase == 'pick' && picked)
          BusinessPickedSection(
            country: country,
            name: s.registrationName ?? '',
            registrationNumber: regNumber,
            isSandbox: isSandbox,
            onChange: () {
              // Back to the search rather than an undo: they are changing
              // WHICH company this is about, and the fields belong to the old
              // one.
              _set('registrationNumber', '');
              _set('registrationName', '');
            },
          ),

        if (_phase == 'details')
          BusinessDetailsFields(
            productDef: productDef,
            regHint: regHint,
            numberValid: numberValid,
            formatOk: formatOk,
            requireName: cfg.requireRegistrationName,
            country: country,
            geoCountry: s.serverConfig.geoCountry,
            modes: modes,
            showCompanyInfo: showCompanyInfo,
            showContactEmail: showContactEmail,
            regCtrl: _regCtrl,
            nameCtrl: _nameCtrl,
            contactEmailCtrl: _contactEmailCtrl,
            infoCtrls: _infoCtrls,
            phoneValue: s.businessPhone ?? '',
            contactEmailValid: (s.businessContactEmail ?? '').trim().isEmpty ||
                isValidContactEmail((s.businessContactEmail ?? '').trim()),
            onChanged: _set,
          ),

        if (checkPanelVisible(s.businessCheck.status)) ...[
          const SizedBox(height: MyazaSpacing.lg),
          BusinessCheckPanel(status: s.businessCheck.status),
        ],

        const SizedBox(height: MyazaSpacing.lg),
        MyazaButton(
          label: checking
              ? 'Checking…'
              : _phase == 'details'
                  ? 'Confirm details & continue'
                  : 'Continue',
          isLoading: checking,
          onPressed:
              !isFormValid || checking ? null : () => _persistAndContinue(country, product),
        ),
      ],
    );
  }

  /// Persist the resolved country/product so the submission uses exactly what
  /// was on screen — only when different: these are identity keys, and writing
  /// an unchanged value would needlessly reset the check we just ran.
  void _persistAndContinue(String country, String product) {
    final s = ref.read(kYCNotifierProvider);
    if (s.businessCountry != country) _set('country', country);
    if (s.businessProduct != product) _set('product', product);
    _onContinue();
  }
}
