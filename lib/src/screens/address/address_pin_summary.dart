import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/address_collection.dart';
import '../../config/address_flow.dart';
import '../../config/theme.dart';
import '../../widgets/line_skeleton.dart';

/// How many of the applicant's own details are filled in — every editable
/// claim on the edit-details form counts.
int addressDetailCount(AddressState? address) {
  if (address == null) return 0;
  return [
    address.propertyNumber,
    address.street,
    address.unit,
    address.propertyName,
    address.directions,
    address.neighbourhood,
    address.city,
    address.state,
    address.postcode,
  ].where((value) => (value ?? '').trim().isNotEmpty).length;
}

/// The secondary line under the address: what has been added, or what would
/// help. Pluralised here so the two SDKs cannot drift on the wording.
String addressDetailSummary(AddressState? address) {
  final count = addressDetailCount(address);
  if (count == 0) {
    return 'A house number and directions help someone find it';
  }
  return count == 1 ? '1 detail added' : '$count details added';
}

/// The pin's summary row: the composed address line, what has been added to
/// it, and the way into the details sheet.
class AddressPinSummary extends StatelessWidget {
  final AddressState? address;

  /// Null disables the button: every field the sheet edits describes a place,
  /// and without a pin there is no place yet.
  final VoidCallback? onEdit;

  /// A reverse geocode is out, so an empty line means "coming", not "none".
  final bool labelling;

  const AddressPinSummary({
    super.key,
    required this.address,
    this.labelling = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final a = address;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Three states, and none is a coordinate pair: no pin, a pin
                // whose address is still being read (a skeleton line at the
                // text's own height, so nothing moves when the words land),
                // and a pin the geocoder had no address for.
                Builder(builder: (context) {
                  final line = a == null ? '' : displayAddressLine(a);
                  final pending = a != null && line.isEmpty && labelling;
                  final style = text.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: line.isEmpty ? colors.textSecondary : null,
                  );
                  if (pending) {
                    return LineSkeleton(label: kAddressLinePending, style: style);
                  }
                  final title = a == null
                      ? 'No pin placed yet'
                      : line.isNotEmpty
                          ? line
                          : kAddressLineUnavailable;
                  // The answer fades in where the skeleton was, left-aligned
                  // so a shorter line never hops sideways mid-swap.
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: Text(
                      title,
                      key: ValueKey(title),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
                const SizedBox(height: 2),
                Text(addressDetailSummary(a),
                    style:
                        text.bodySmall.copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: MyazaSpacing.sm),
          Material(
            color: Colors.transparent,
            // Web's `h-9 rounded-lg px-3 text-sm`: 36 high, an 8 radius,
            // 14px text, which RN draws as radius.xs + bodyMedium.
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(MyazaRadius.xs),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(MyazaRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.pencilLine,
                        size: 14,
                        color: onEdit == null ? colors.gray400 : colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Edit details',
                      style: text.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            onEdit == null ? colors.gray400 : colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
