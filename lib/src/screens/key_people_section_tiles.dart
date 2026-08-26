import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../widgets/dashed_border.dart';

// The two tiles a section offers: a quick-add chip for someone already on the
// list, and the dashed add tile. Split from key_people_section (200-line rule).

/// A person already on the list, offered one tap to also wear this section's
/// hat. Retyping them would be a second person as far as the register cares.
class KeyPeopleQuickAddChip extends StatelessWidget {
  const KeyPeopleQuickAddChip({super.key, required this.entry, required this.onTap});

  final KeyPersonEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(MyazaRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.isCorporate ? LucideIcons.building2 : LucideIcons.user,
                  size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  entry.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium.copyWith(
                      color: colors.textDark, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.primary100,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.plus, size: 12, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same tight dashed language as the document slots.
class KeyPeopleAddTile extends StatelessWidget {
  const KeyPeopleAddTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
        child: CustomPaint(
          painter: DashedRoundedBorder(
            color: colors.border,
            radius: MyazaRadius.sm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Text(label,
                    style: text.bodyMedium.copyWith(
                        color: colors.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
