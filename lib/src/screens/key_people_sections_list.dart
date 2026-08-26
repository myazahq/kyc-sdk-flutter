import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/key_people_section_defs.dart';
import '../config/key_people_sections.dart';
import '../config/theme.dart';
import 'key_people_section.dart';
import 'key_people_ubo_exemption.dart';

// The stacked sections with their shared-list plumbing: quick-add grants an
// existing person the section's hat, and the card's X takes them out of that
// section, dropping just the hat when membership rested on it, or the whole
// person when a declared stake (or a last remaining hat) is what holds them
// there. Mirrors the RN SDK's KeyPeopleSectionsList and the web SDK's 1:1.

class KeyPeopleSectionsList extends StatelessWidget {
  const KeyPeopleSectionsList({
    super.key,
    required this.sections,
    required this.rows,
    required this.threshold,
    required this.emailRequiredFor,
    required this.uboUnidentifiable,
    required this.canAdd,
    required this.onRows,
    required this.onAdd,
    required this.onEdit,
    required this.onExemption,
  });

  final List<KeyPeopleSectionDef> sections;
  final List<KeyPersonEntry> rows;
  final double threshold;
  final Set<KeyPersonRole> emailRequiredFor;
  final bool uboUnidentifiable;
  final bool canAdd;
  final void Function(List<KeyPersonEntry> next) onRows;
  final void Function(KeyPeopleSection section) onAdd;
  final void Function(KeyPeopleSection section, int index) onEdit;
  final void Function(bool next) onExemption;

  void _removeFromSection(KeyPeopleSection section, int index) {
    final next = withoutSection(rows[index], section, threshold);
    if (next == null) {
      onRows([
        for (var i = 0; i < rows.length; i++)
          if (i != index) rows[i],
      ]);
      return;
    }
    onRows([
      for (var i = 0; i < rows.length; i++) i == index ? next : rows[i],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final members = sectionMembers(rows, threshold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.lg),
              child: Divider(height: 1, thickness: 1, color: colors.border),
            ),
          Builder(builder: (context) {
            final def = sections[i];
            final isUbos = def.key == KeyPeopleSection.ubos;
            // The exemption is a claim that there are no UBOs to name, so
            // while it stands the section stops inviting more.
            final suppressed = isUbos && uboUnidentifiable;

            return KeyPeopleSectionView(
              section: def.key,
              title: def.title,
              description: def.description,
              rows: rows,
              members: members[def.key]!,
              quickAdd: suppressed
                  ? const []
                  : quickAddCandidates(rows, def.key, threshold),
              emailRequiredFor: emailRequiredFor,
              addLabel: def.addLabel,
              canAdd: canAdd && !suppressed,
              onAdd: () => onAdd(def.key),
              onEdit: (index) => onEdit(def.key, index),
              onRemove: (index) => _removeFromSection(def.key, index),
              onQuickAdd: (index) => onRows([
                for (var j = 0; j < rows.length; j++)
                  j == index ? grantRole(rows[j], def.key) : rows[j],
              ]),
              footer: isUbos
                  ? KeyPeopleUboExemption(
                      checked: uboUnidentifiable,
                      hasUbos: members[KeyPeopleSection.ubos]!.isNotEmpty,
                      onChanged: onExemption,
                    )
                  : null,
            );
          }),
        ],
      ],
    );
  }
}
