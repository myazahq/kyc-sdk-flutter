import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/theme.dart';
import '../widgets/country_flag.dart';

// ─── The company the applicant picked, standing where the search box was ─────
//
// Choosing a row IS the choice: the card replaces the list, and Change swaps
// back. A separate confirm button meant two primary buttons on screen at once,
// and the card already shows what was picked — the confirmation is the screen
// after, not a button before it. Dimensions mirror the web and RN SDKs' picked
// card (40px badge, 12px padding and gaps).

class BusinessPickedCard extends StatelessWidget {
  final String country;
  final String name;
  final String registrationNumber;
  final VoidCallback onChange;

  const BusinessPickedCard({
    super.key,
    required this.country,
    required this.name,
    required this.registrationNumber,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business', style: text.label),
        const SizedBox(height: MyazaSpacing.sm),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: colors.primary),
            color: colors.primary50,
            borderRadius: BorderRadius.circular(MyazaRadius.sm),
          ),
          child: Row(
            children: [
              // The badge: the company as a thing that has been chosen, in the
              // same filled-circle language the picked rows of every other
              // list use.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.building2,
                    size: 20, color: colors.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.trim().isEmpty
                          ? 'We will confirm the name with the register'
                          : name.trim(),
                      style: text.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        MyazaCountryFlag(country: country, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          registrationNumber,
                          style: text.bodySmall
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: onChange,
                borderRadius: BorderRadius.circular(MyazaRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: MyazaSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.pencil,
                          size: 14, color: colors.textDark),
                      const SizedBox(width: 6),
                      Text(
                        'Change',
                        style: text.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
