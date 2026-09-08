import 'package:flutter/material.dart';

import '../../config/address_field_modes.dart';
import '../../config/theme.dart';
import 'address_detail_fields.dart';

// ─── The "Area and region" section of the edit-details sheet ─────────────────
//
// 200-line split from address_detail_fields.dart. Each field honours its
// workflow mode (address_field_modes.dart): 'off' hides it, 'required' marks
// it, and the section disappears whole when nothing in it is offered.
// Mirrors the web SDK's AreaFields and the RN twin; keep the three in
// lockstep.

/// Two fields side by side, or the one of them the workflow offers.
Widget addressFieldPair(Widget? left, Widget? right) {
  if (left == null && right == null) return const SizedBox.shrink();
  if (left == null || right == null) return left ?? right!;
  return Row(
    // TOP-aligned: the country tile carries a caption the field beside it
    // does not, so bottom alignment lifted its label and box out of line.
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: MyazaSpacing.sm),
      Expanded(child: right),
    ],
  );
}

/// The "Area and region" section. Each field honours its workflow mode:
/// 'off' hides it, 'required' marks it. Nothing when all four are off.
class AddressAreaFields extends StatelessWidget {
  final Map<String, AddressFieldMode> modes;
  final TextEditingController neighbourhood;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController postcode;
  final String? country;
  final ValueChanged<AddressDetailsPatch> onChanged;

  const AddressAreaFields({
    super.key,
    required this.modes,
    required this.neighbourhood,
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
    required this.onChanged,
  });

  bool _on(String key) => modes[key] != AddressFieldMode.off;
  bool _req(String key) => modes[key] == AddressFieldMode.required;

  @override
  Widget build(BuildContext context) {
    if (!_on('neighbourhood') && !_on('city') && !_on('state') && !_on('postcode')) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MyazaSpacing.md),
        const AddressSectionHeading('Area and region'),
        if (_on('neighbourhood')) ...[
          AddressEditField(label: 'Neighbourhood', hint: 'e.g. Idim Ita', maxLength: 80, required: _req('neighbourhood'), controller: neighbourhood, onChanged: (v) => onChanged(AddressDetailsPatch(neighbourhood: v))),
          const SizedBox(height: MyazaSpacing.sm),
        ],
        addressFieldPair(
          _on('city') ? AddressEditField(label: 'City', hint: 'e.g. Calabar', maxLength: 80, required: _req('city'), controller: city, onChanged: (v) => onChanged(AddressDetailsPatch(city: v))) : null,
          _on('state') ? AddressEditField(label: 'State', hint: 'e.g. Cross River', maxLength: 80, required: _req('state'), controller: state, onChanged: (v) => onChanged(AddressDetailsPatch(state: v))) : null,
        ),
        if (_on('city') || _on('state')) const SizedBox(height: MyazaSpacing.sm),
        addressFieldPair(
          _on('postcode') ? AddressEditField(label: 'Area code', hint: 'e.g. 540281', maxLength: 12, required: _req('postcode'), controller: postcode, onChanged: (v) => onChanged(AddressDetailsPatch(postcode: v))) : null,
          AddressCountryRow(country: country),
        ),
      ],
    );
  }
}
