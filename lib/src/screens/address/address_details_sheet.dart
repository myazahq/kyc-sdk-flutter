import 'package:flutter/material.dart';

import '../../config/address_collection.dart';
import '../../config/address_field_modes.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/myaza_button.dart';
import '../../widgets/themed_sheet.dart';
import 'address_area_fields.dart';
import 'address_detail_fields.dart';

export 'address_detail_fields.dart' show AddressDetailsPatch;

// ─── The EDIT-DETAILS sheet ──────────────────────────────────────────────────
//
// OkHi-style (user decision 2026-08-31): everything on the address is
// editable. Two grouped sections — street and building, then area and region —
// with the map's answer prefilling the area fields so the applicant corrects
// rather than retypes. An untouched prefill is never stored as their claim:
// the parent only receives what they actually edit.
//
// Each typed field honours its workflow mode (address_field_modes.dart):
// 'off' hides it, 'required' marks it and holds the pin step's Continue.
// Mirrors the web and RN SDKs' DetailsSheet; keep the three in lockstep. The
// SDK's own floating sheet supplies the handle and close control, so this is
// only the body.

Future<void> showAddressDetailsSheet(
  BuildContext context, {
  required bool isBusiness,
  required bool directionsRequired,
  required AddressParts? parts,
  required String? country,
  required AddressState address,
  required AddressCollectionConfig? config,
  required ValueChanged<AddressDetailsPatch> onChanged,
}) {
  return showMyazaSheet<void>(
    context,
    isScrollControlled: true,
    builder: (_) => _AddressDetailsBody(
      isBusiness: isBusiness,
      directionsRequired: directionsRequired,
      parts: parts,
      country: country,
      address: address,
      modes: addressFieldModes(config),
      onChanged: onChanged,
    ),
  );
}

class _AddressDetailsBody extends StatefulWidget {
  final bool isBusiness;
  final bool directionsRequired;
  final AddressParts? parts;
  final String? country;
  final AddressState address;
  final Map<String, AddressFieldMode> modes;
  final ValueChanged<AddressDetailsPatch> onChanged;

  const _AddressDetailsBody({
    required this.isBusiness,
    required this.directionsRequired,
    required this.parts,
    required this.country,
    required this.address,
    required this.modes,
    required this.onChanged,
  });

  @override
  State<_AddressDetailsBody> createState() => _AddressDetailsBodyState();
}

class _AddressDetailsBodyState extends State<_AddressDetailsBody> {
  // Typed wins (a cleared field STAYS cleared); the map's answer fills the
  // gap only while the applicant has never touched the field (null).
  String _shown(String? typed, String? part) => typed ?? (part ?? '').trim();

  late final _number = TextEditingController(text: widget.address.propertyNumber);
  late final _street = TextEditingController(text: _shown(widget.address.street, widget.parts?.street));
  late final _unit = TextEditingController(text: widget.address.unit ?? '');
  late final _building = TextEditingController(text: widget.address.propertyName);
  late final _directions = TextEditingController(text: widget.address.directions);
  late final _neighbourhood = TextEditingController(text: _shown(widget.address.neighbourhood, widget.parts?.area));
  late final _city = TextEditingController(text: _shown(widget.address.city, widget.parts?.city));
  late final _state = TextEditingController(text: _shown(widget.address.state, widget.parts?.state));
  late final _postcode = TextEditingController(text: _shown(widget.address.postcode, widget.parts?.postcode));

  bool _on(String key) => widget.modes[key] != AddressFieldMode.off;
  bool _req(String key) => widget.modes[key] == AddressFieldMode.required;

  @override
  void dispose() {
    for (final c in [_number, _street, _unit, _building, _directions, _neighbourhood, _city, _state, _postcode]) {
      c.dispose();
    }
    super.dispose();
  }

  AddressEditField? _field(String key, {required String label, required String hint, required int maxLength, required TextEditingController controller, required AddressDetailsPatch Function(String) patch}) {
    if (!_on(key)) return null;
    return AddressEditField(label: label, hint: hint, maxLength: maxLength, required: _req(key), controller: controller, onChanged: (v) => widget.onChanged(patch(v)));
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final anyRequired = widget.modes.values.any((m) => m == AddressFieldMode.required);
    final streetSection = _on('propertyNumber') || _on('street') || _on('unit') || _on('propertyName');
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MyazaSpacing.md, 0, MyazaSpacing.md, MyazaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit your address', style: text.heading3),
              const SizedBox(height: 2),
              Text(
                anyRequired
                    ? 'Correct anything the map got wrong. Fields marked * are required.'
                    : 'Correct anything the map got wrong. Every field is optional, '
                        'and it all helps someone find the door.',
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: MyazaSpacing.md),
              if (streetSection) const AddressSectionHeading('Street and building'),
              addressFieldPair(
                _field('propertyNumber', label: 'Number', hint: 'e.g. 11', maxLength: 20, controller: _number, patch: (v) => AddressDetailsPatch(propertyNumber: v)),
                _field('street', label: 'Street name', hint: 'e.g. Awolowo Road', maxLength: 120, controller: _street, patch: (v) => AddressDetailsPatch(street: v)),
              ),
              if (_on('propertyNumber') || _on('street')) const SizedBox(height: MyazaSpacing.sm),
              addressFieldPair(
                _field('unit', label: 'Unit', hint: 'e.g. Flat 4', maxLength: 30, controller: _unit, patch: (v) => AddressDetailsPatch(unit: v)),
                _field('propertyName', label: 'Building name', hint: 'e.g. Sunrise Villa', maxLength: 80, controller: _building, patch: (v) => AddressDetailsPatch(propertyName: v)),
              ),
              if (_on('unit') || _on('propertyName')) const SizedBox(height: MyazaSpacing.sm),
              AddressEditField(
                label: '${widget.isBusiness ? 'Directions to the entrance' : 'Directions to this address'}'
                    '${widget.directionsRequired ? '' : ' (optional)'}',
                hint: 'e.g. black gate opposite the kiosk, second building after the junction',
                maxLength: 500,
                multiline: true,
                controller: _directions,
                onChanged: (v) => widget.onChanged(AddressDetailsPatch(directions: v)),
              ),
              AddressAreaFields(
                modes: widget.modes,
                neighbourhood: _neighbourhood,
                city: _city,
                state: _state,
                postcode: _postcode,
                country: widget.country,
                onChanged: widget.onChanged,
              ),
              const SizedBox(height: MyazaSpacing.lg),
              MyazaButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}
