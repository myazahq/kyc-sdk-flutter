import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/address_collection.dart';
import '../../config/address_flow.dart';
import '../../config/theme.dart';
import '../../utils/map_tiles.dart';
import '../../widgets/line_skeleton.dart';
import '../../widgets/presence_milestones.dart';
import 'address_review_map.dart';
import 'address_review_thumb.dart';

// ─── The confirmation card ───────────────────────────────────────────────────
//
// One composed card: a read-only map, the entrance imagery hanging over its
// bottom edge like a photo clipped to a document, and the address underneath
// as the card's own heading, in the success card's header-band language.
// Mirrors the web and RN review cards; the map surface lives in
// address_review_map.dart and the thumbnails in address_review_thumb.dart.

// Web's geometry: the band clears the thumbnails with pr-32 / min-h-[4.25rem].
// EXACTLY 128, no breathing room added: 12 more starved the "Pinned address"
// pill on a 360dp phone (the S24, 2026-09-08) and a red overflow stripe stood
// on the confirmation screen. RN keeps the same number.
const double _kBandClearance = 128;
const double _kBandMinHeight = 68;

class AddressReviewCard extends StatelessWidget {
  final AddressState? address;
  final MapLatLng? pin;
  final bool isBusiness;
  final String? photoPreviewPath;
  final VoidCallback onEdit;

  /// SANDBOX shows the placeholder instead of the tiles.
  final bool vendorsStubbed;

  /// A reverse geocode is out, so an empty line means "coming", not "none".
  final bool labelling;

  /// The framed map's URL, the pinned location as a picture, its headers.
  final String? mapsFrameUrl;
  final String? staticMapUrl;
  final Map<String, String> imageHeaders;

  /// The framed Street View entrance, fetched through the server by the step.
  /// The photo leads; this takes the smaller slot, or the big one alone.
  final Uint8List? streetViewThumb;

  const AddressReviewCard({
    super.key,
    required this.address,
    required this.pin,
    required this.isBusiness,
    required this.photoPreviewPath,
    required this.onEdit,
    this.vendorsStubbed = false,
    this.labelling = false,
    this.streetViewThumb,
    this.mapsFrameUrl,
    this.staticMapUrl,
    this.imageHeaders = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final a = address;
    final directions = (a?.directions ?? '').trim();
    final hero = (photoPreviewPath ?? '').trim();
    final frame = streetViewThumb;
    final hasHero = hero.isNotEmpty;
    final showFrameAsHero = !hasHero && frame != null;
    final showFrameBeside = hasHero && frame != null;
    // Something hangs over the map's bottom edge: the band clears it, so Edit
    // sits beside the entrance rather than under it.
    final hangs = hasHero || showFrameAsHero;
    final line = a == null ? '' : displayAddressLine(a);
    final lineStyle = text.body.copyWith(fontWeight: FontWeight.w600, height: 1.3);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pin != null)
                // The whole map is the way back to the pin step.
                Semantics(
                  button: true,
                  label: 'Edit the pinned location',
                  child: GestureDetector(
                    onTap: onEdit,
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(MyazaRadius.md - 1),
                      ),
                      child: AddressReviewMap(
                        pin: pin!,
                        vendorsStubbed: vendorsStubbed,
                        mapsFrameUrl: mapsFrameUrl,
                        staticMapUrl: staticMapUrl,
                        imageHeaders: imageHeaders,
                      ),
                    ),
                  ),
                ),
              Container(
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
                              leading: Icon(LucideIcons.mapPin, size: 12, color: colors.primary),
                              label: isBusiness ? 'Pinned premises' : 'Pinned address',
                            ),
                            const SizedBox(height: MyazaSpacing.xs),
                            // Never coordinates: an unread pin shows a skeleton
                            // line while its address is still coming.
                            if (a != null && line.isEmpty && labelling)
                              LineSkeleton(label: kAddressLinePending, style: lineStyle, widthFactor: 0.7)
                            else
                              Text(
                                a == null
                                    ? 'No pin placed'
                                    : line.isNotEmpty
                                        ? line
                                        : kAddressLineUnavailable,
                                style: lineStyle,
                              ),
                            if (directions.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text('“$directions”',
                                  style: text.bodySmall.copyWith(color: colors.textSecondary, height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: MyazaSpacing.sm),
                      Semantics(
                        button: true,
                        label: 'Edit',
                        child: InkWell(
                          onTap: onEdit,
                          borderRadius: BorderRadius.circular(MyazaRadius.xs),
                          child: Padding(
                            // No side padding: every pixel of the row is the
                            // pill's on a 360dp phone.
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('Edit', style: text.bodyMedium.copyWith(color: colors.primary)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // The entrance, painted LAST so the half hanging over the band is
          // not covered by it. Both thumbnails share one bottom edge, 40 below
          // the map, exactly as the web card's -bottom-10 does.
          if (pin != null && hangs)
            Positioned(
              right: 16,
              top: kReviewMapHeight + kReviewOverhang - kReviewHeroSize,
              child: hasHero ? ReviewEntranceThumb(path: hero) : ReviewEntranceThumb(bytes: frame),
            ),
          if (pin != null && showFrameBeside)
            Positioned(
              right: 144,
              top: kReviewMapHeight + kReviewOverhang - kReviewSecondSize,
              child: ReviewEntranceThumb(bytes: frame, size: kReviewSecondSize),
            ),
        ],
      ),
    );
  }
}
