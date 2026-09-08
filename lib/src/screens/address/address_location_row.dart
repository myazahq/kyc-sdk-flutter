import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/theme.dart';

/// "Use my current location" as a proper ROW, not a button pretending to be
/// two: a medallion showing the fix's state, a title with the RESOLVED ADDRESS
/// underneath — so the applicant can see where it will take them before
/// tapping — and a chevron saying this goes somewhere.
///
/// Shared by the search step and the pin step, the latter only while no pin
/// exists. Mirrors the web and RN SDKs' CurrentLocationRow.
class CurrentLocationRow extends StatelessWidget {
  /// The device's resolved current address, when known.
  final String? hint;
  final bool locating;
  final VoidCallback onTap;

  const CurrentLocationRow({
    super.key,
    required this.hint,
    required this.locating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final resolved = (hint ?? '').trim();
    final hasHint = resolved.isNotEmpty;
    return Material(
      color: colors.backgroundSecondary,
      borderRadius: BorderRadius.circular(MyazaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyazaRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(MyazaRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasHint
                      ? colors.primary
                      : colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: locating && !hasHint
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.primary),
                      )
                    : Icon(
                        hasHint ? LucideIcons.mapPin : LucideIcons.locateFixed,
                        size: 18,
                        color: hasHint ? colors.onPrimary : colors.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Use my current location',
                        style:
                            text.label.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      hasHint
                          ? resolved
                          : (locating
                              ? 'Finding your location…'
                              : 'Lands the pin right where you are'),
                      style:
                          text.bodySmall.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MyazaSpacing.sm),
              Icon(LucideIcons.chevronRight,
                  size: 16, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The DEMOTED form of the row above, for once a pin exists: locating again is
/// then a rare corrective action, so it becomes a pill ON the map, bottom
/// centre where the eye and thumb already are (the corners belong to
/// attribution and zoom). The full-width row invited a mistaken tap that
/// yanked a confirmed address to wherever the phone happened to be.
class LocateOnMapButton extends StatelessWidget {
  final bool locating;
  final VoidCallback onTap;

  const LocateOnMapButton({
    super.key,
    required this.locating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Semantics(
      button: true,
      label: 'Move the pin to my current location',
      child: Material(
        color: colors.background,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        elevation: 2,
        child: InkWell(
          onTap: locating ? null : onTap,
          borderRadius: BorderRadius.circular(MyazaRadius.full),
          // Web's `h-10 pl-3 pr-3.5 gap-2 shadow-md`, the numbers RN draws.
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 12, right: 14),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(MyazaRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locating)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.textSecondary),
                  )
                else
                  Icon(LucideIcons.locateFixed,
                      size: 16, color: colors.primary),
                const SizedBox(width: MyazaSpacing.sm),
                Text(
                  locating ? 'Finding you…' : 'Use my location',
                  style: text.bodySmall.copyWith(
                      fontWeight: FontWeight.w600, color: colors.textDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
