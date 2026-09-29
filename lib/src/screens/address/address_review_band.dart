import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../config/address_flow.dart';
import '../../widgets/icons/icons.dart';
import '../../widgets/line_skeleton.dart';
import '../../widgets/presence_milestones.dart';
import '../../i18n/text_scope.dart';

// ─── The band under the review card's map ────────────────────────────────────
//
// The address, in the success card's header-band language (200-line split
// from address_review_card.dart; RN's ReviewAddressBand.tsx is the twin).
//
// Web's geometry: the band clears the thumbnails with pr-32 / min-h-[4.25rem].
// EXACTLY 128, no breathing room added: 12 more starved the "Pinned address"
// pill on a 360dp phone (the S24, 2026-09-08) and a red overflow stripe stood
// on the confirmation screen. RN keeps the same number.
//
// The 128 also put Edit flush against the entrance photo's edge (the photo
// is 112 wide, 16 from the card's edge), so when something hangs over the
// band Edit moves under the address, clear of the photo, and the pill gets
// the width Edit used to take.
const double _kBandClearance = 128;
const double _kBandMinHeight = 68;

class AddressReviewBand extends StatelessWidget {
  final bool isBusiness;
  final bool hasAddress;

  /// The composed line; empty while the pin has no readable address yet.
  final String line;
  final bool labelling;
  final String directions;

  /// Something hangs over the map's bottom edge: the band clears it.
  final bool hangs;
  final VoidCallback onEdit;

  const AddressReviewBand({
    super.key,
    required this.isBusiness,
    required this.hasAddress,
    required this.line,
    required this.labelling,
    required this.directions,
    required this.hangs,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final lineStyle =
        text.body.copyWith(fontWeight: FontWeight.w600, height: 1.3);
    final editLink = Semantics(
      button: true,
      label: context.kycText('address.review.edit'),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(MyazaRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(context.kycText('address.review.edit'),
              style: text.bodyMedium.copyWith(color: colors.primary)),
        ),
      ),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(MyazaRadius.md - 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        MyazaSpacing.md,
        MyazaSpacing.md,
        hangs ? _kBandClearance : MyazaSpacing.md,
        MyazaSpacing.md,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hangs ? _kBandMinHeight : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PresenceBadge(
                    leading: MyazaIcon(MyazaIcons.mapPin,
                        size: 12, color: colors.primary),
                    label: context.kycText(isBusiness
                        ? 'address.review.badge.business'
                        : 'address.review.badge'),
                  ),
                  const SizedBox(height: MyazaSpacing.xs),
                  // Never coordinates: an unread pin shows a skeleton
                  // line while its address is still coming.
                  if (hasAddress && line.isEmpty && labelling)
                    LineSkeleton(
                        label: kAddressLinePending,
                        style: lineStyle,
                        widthFactor: 0.7)
                  else
                    Text(
                      !hasAddress
                          ? 'No pin placed'
                          : line.isNotEmpty
                              ? line
                              : kAddressLineUnavailable,
                      style: lineStyle,
                    ),
                  if (directions.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('“$directions”',
                        style: text.bodySmall.copyWith(
                            color: colors.textSecondary, height: 1.4)),
                  ],
                  if (hangs) ...[
                    const SizedBox(height: MyazaSpacing.sm),
                    editLink,
                  ],
                ],
              ),
            ),
            // Beside the address only when nothing hangs over the
            // band. With an entrance photo there, the 128 clearance
            // put Edit flush against the photo's edge, and widening
            // it starves the pill on a 360dp phone; so Edit moves
            // under the address instead (the column above).
            if (!hangs) ...[
              const SizedBox(width: MyazaSpacing.sm),
              editLink,
            ],
          ],
        ),
      ),
    );
  }
}
