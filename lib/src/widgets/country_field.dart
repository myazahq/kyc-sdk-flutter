import 'package:flutter/material.dart';

import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'country_flag.dart';
import 'icons/icons.dart';
import 'dial_code_picker.dart' show showCountryPicker;

// ─── Country field ────────────────────────────────────────────────────────────
//
// A country select field: a MyazaSelect-styled collapsed trigger (flag + name
// + chevron) that opens THE country sheet — the phone field's dial-code picker
// minus the dial codes (keyboard-aware, autofocused search, results pinned
// above the keys). Used wherever a country is picked from a flat list (the
// key-person "where their ID was issued", the KYB "Country of registration"),
// so every country picker in the flow feels identical.

class CountryField extends StatelessWidget {
  /// ISO-2 of the current pick; empty shows the placeholder.
  final String country;
  final ValueChanged<String> onChanged;

  /// Restricts the pickable list (a workflow's registry countries).
  /// Null ⇒ every named ISO country.
  final Iterable<String>? codes;

  final String placeholder;

  /// The visitor's inferred country, pinned on top of the sheet as
  /// "Your location".
  final String? geoCountry;

  /// Region headers between the rows, the country-select step's way.
  final bool grouped;

  const CountryField({
    super.key,
    required this.country,
    required this.onChanged,
    this.codes,
    this.placeholder = 'Select a country',
    this.geoCountry,
    this.grouped = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final hasValue = country.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
        onTap: () async {
          final picked = await showCountryPicker(
            context,
            hasValue ? country : null,
            codes: codes,
            pinned: geoCountry,
            grouped: grouped,
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MyazaSpacing.md,
            vertical: MyazaSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(MyazaRadius.sm),
          ),
          child: Row(
            children: [
              if (hasValue) ...[
                MyazaCountryFlag(country: country, size: 20),
                const SizedBox(width: MyazaSpacing.sm),
              ],
              Expanded(
                child: Text(
                  hasValue ? countryLabel(country) : placeholder,
                  overflow: TextOverflow.ellipsis,
                  style: hasValue
                      ? text.label
                      : text.label.copyWith(color: colors.textMuted),
                ),
              ),
              const SizedBox(width: MyazaSpacing.sm),
              MyazaIcon(MyazaIcons.chevronDown,
                  size: 18, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
