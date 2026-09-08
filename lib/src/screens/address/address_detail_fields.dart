import 'package:flutter/material.dart';

import '../../config/id_types.dart';
import '../../config/theme.dart';
import '../../widgets/country_flag.dart';
import '../../widgets/myaza_input.dart';

// ─── The edit-details form primitives ────────────────────────────────────────
//
// 200-line split from address_details_sheet.dart. Mirrors the web SDK's
// DetailsSheetFields and the RN twin — keep the three in lockstep. Every
// field is optional unless the WORKFLOW requires it (address_field_modes.dart):
// an applicant in an unnumbered compound cannot answer a number, so only a
// field the org deliberately required may hold them.

/// The patch a sheet edit produces. Each field is null when untouched, so one
/// write never clears the others.
class AddressDetailsPatch {
  final String? street;
  final String? propertyNumber;
  final String? unit;
  final String? propertyName;
  final String? directions;
  final String? neighbourhood;
  final String? city;
  final String? state;
  final String? postcode;

  const AddressDetailsPatch({
    this.street,
    this.propertyNumber,
    this.unit,
    this.propertyName,
    this.directions,
    this.neighbourhood,
    this.city,
    this.state,
    this.postcode,
  });
}

/// One editable claim field. The controller carries the shown value (typed,
/// else the map's prefill); the parent stores whatever the applicant edits.
class AddressEditField extends StatelessWidget {
  final String label;
  final String? hint;
  final int maxLength;
  final bool multiline;

  /// Workflow-required: marked, and the pin step's Continue holds until it
  /// shows a value.
  final bool required;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const AddressEditField({
    super.key,
    required this.label,
    required this.maxLength,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.multiline = false,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) => MyazaInput(
        label: label,
        required: required,
        hint: hint,
        controller: controller,
        maxLength: maxLength,
        maxLines: multiline ? 4 : 1,
        onChanged: onChanged,
      );
}

/// A grouped-section heading, matching the web sheet's uppercase caption.
class AddressSectionHeading extends StatelessWidget {
  final String title;

  const AddressSectionHeading(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.only(bottom: MyazaSpacing.sm),
      child: Text(
        title.toUpperCase(),
        style: text.bodySmall.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Read-only country row: the flow's country is a fact of the verification,
/// not an address field — visually distinct from a disabled input.
class AddressCountryRow extends StatelessWidget {
  final String? country;

  const AddressCountryRow({super.key, required this.country});

  @override
  Widget build(BuildContext context) {
    final code = country;
    if (code == null || code.isEmpty) return const SizedBox.shrink();
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The SAME label treatment MyazaInput gives its own fields, so the
        // tile's box lines up with the input beside it.
        Text('Country', style: text.label),
        const SizedBox(height: MyazaSpacing.xs),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm + 4),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(MyazaRadius.md),
          ),
          child: Row(
            children: [
              MyazaCountryFlag(country: code, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  countryDisplayName(code),
                  style: text.label.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('From your verification',
            style: text.bodySmall.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

/// The country's display name — the SDK's own catalogue label, the same one
/// every picker in the flow uses, with the ISO code standing in for a country
/// it has no name for.
String countryDisplayName(String code) => countryLabel(code.toUpperCase());
