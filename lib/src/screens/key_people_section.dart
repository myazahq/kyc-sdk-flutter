import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/key_people_sections.dart';
import '../config/theme.dart';
import 'key_people_section_tiles.dart';
import 'key_person_card.dart';

// One section of the key-people step: heading, plain-language definition,
// member cards, quick-add chips for people already entered elsewhere, and the
// dashed add tile. Sections are VIEWS over one shared list
// (key_people_sections.dart). Mirrors the RN SDK's KeyPeopleSection and the
// web SDK's 1:1.

class KeyPeopleSectionView extends StatelessWidget {
  const KeyPeopleSectionView({
    super.key,
    required this.section,
    required this.title,
    required this.description,
    required this.rows,
    required this.members,
    required this.quickAdd,
    required this.emailRequiredFor,
    required this.addLabel,
    required this.canAdd,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onQuickAdd,
    this.footer,
  });

  final KeyPeopleSection section;
  final String title;
  final String description;
  final List<KeyPersonEntry> rows;
  final List<int> members;
  final List<int> quickAdd;
  final Set<KeyPersonRole> emailRequiredFor;
  final String addLabel;
  final bool canAdd;
  final VoidCallback onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;
  final void Function(int index) onQuickAdd;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.heading3),
        const SizedBox(height: 2),
        Text(description,
            style: text.bodyMedium.copyWith(color: colors.textSecondary)),

        if (members.isNotEmpty) ...[
          const SizedBox(height: MyazaSpacing.sm + 4),
          for (final index in members)
            KeyPersonCard(
              entry: rows[index],
              emailRequiredFor: emailRequiredFor,
              roleLabel: kSectionRole[section]!.label,
              onTap: () => onEdit(index),
              onRemove: () => onRemove(index),
            ),
        ],

        if (quickAdd.isNotEmpty && canAdd) ...[
          const SizedBox(height: MyazaSpacing.sm + 4),
          Text(
            'Quick add from people you already entered',
            style: text.bodySmall.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: MyazaSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final index in quickAdd)
                KeyPeopleQuickAddChip(
                  entry: rows[index],
                  onTap: () => onQuickAdd(index),
                ),
            ],
          ),
        ],

        if (canAdd) ...[
          const SizedBox(height: MyazaSpacing.sm + 4),
          KeyPeopleAddTile(label: addLabel, onTap: onAdd),
        ],

        if (footer != null) footer!,
      ],
    );
  }
}
