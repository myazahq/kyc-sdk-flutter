import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/registration_hint.dart';
import '../config/theme.dart';
import '../widgets/myaza_input.dart';
import 'business_company_info_fields.dart';
import 'business_details_parts.dart';

// ─── The DETAILS screen of the business step ──────────────────────────────────
//
// Confirming what the register said. Registration number and name are editable
// here too — this is also where manual entry lands, for the companies no
// search index carries. Split from business_details_screen.dart (200-line
// rule); field order mirrors the web and RN SDKs.

class BusinessDetailsFields extends StatelessWidget {
  final BusinessProduct productDef;
  final RegistrationHint regHint;
  final bool numberValid;
  final bool formatOk;
  final bool requireName;
  final String country;
  final String? geoCountry;
  final Map<CompanyInfoField, CompanyInfoMode> modes;
  final bool showCompanyInfo;
  final bool showContactEmail;
  final TextEditingController regCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController contactEmailCtrl;
  final Map<CompanyInfoField, TextEditingController> infoCtrls;
  final String phoneValue;
  final bool contactEmailValid;
  final void Function(String key, String value) onChanged;

  const BusinessDetailsFields({
    super.key,
    required this.productDef,
    required this.regHint,
    required this.numberValid,
    required this.formatOk,
    required this.requireName,
    required this.country,
    required this.modes,
    required this.showCompanyInfo,
    required this.showContactEmail,
    required this.regCtrl,
    required this.nameCtrl,
    required this.contactEmailCtrl,
    required this.infoCtrls,
    required this.phoneValue,
    required this.contactEmailValid,
    required this.onChanged,
    this.geoCountry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live like the web SDK: a wrong CAC prefix is corrected on the spot,
        // not discovered on Continue. The registry tip fills the same slot
        // until there is an error to show.
        MyazaInput(
          label: productDef.inputLabel,
          controller: regCtrl,
          hint: regHint.placeholder,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          errorText: regCtrl.text.trim().isNotEmpty && !numberValid
              ? (!formatOk && regHint.formatError != null
                  ? regHint.formatError
                  : 'Enter a valid ${productDef.inputLabel.toLowerCase()}.')
              : null,
          helperText: regHint.tip,
          onChanged: (v) => onChanged('registrationNumber', v),
        ),
        const SizedBox(height: MyazaSpacing.md),

        BusinessFieldLabel(
          label: 'Registered business name',
          required: requireName,
        ),
        const SizedBox(height: MyazaSpacing.xs),
        MyazaInput(
          controller: nameCtrl,
          hint: 'Enter the registered business name',
          autocorrect: false,
          onChanged: (v) => onChanged('registrationName', v),
        ),

        if (showCompanyInfo) ...[
          const SizedBox(height: MyazaSpacing.md),
          BusinessCompanyInfoFields(
            modes: modes,
            controllers: infoCtrls,
            country: country,
            geoCountry: geoCountry,
            phoneValue: phoneValue,
            onChanged: (field, value) => onChanged(field.key, value),
          ),
        ],

        if (showContactEmail) ...[
          const SizedBox(height: MyazaSpacing.md),
          BusinessContactEmailField(
            controller: contactEmailCtrl,
            valid: contactEmailValid,
            onChanged: (v) => onChanged('contactEmail', v),
          ),
        ],
      ],
    );
  }
}
