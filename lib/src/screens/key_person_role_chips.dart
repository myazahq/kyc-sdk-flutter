import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/theme.dart';

// The representative form's role chips: real CLASSIFICATIONS, not job titles.
// A title ("CFO", "Board Member") goes in the free-text position field, because
// classification decides who gets screened and invited while a title decides
// nothing.
//
// Multi-select over the entry's role SET, with the last representative hat
// pinned on: unticking it would silently drop the person out of the section
// they are being edited in. Mirrors the RN SDK's KeyPersonRoleChips and the
// web SDK's.

const List<({KeyPersonRole role, String label})> _repRoles = [
  (role: KeyPersonRole.director, label: 'Director'),
  (role: KeyPersonRole.signatory, label: 'Signatory'),
];

class KeyPersonRoleChips extends StatelessWidget {
  const KeyPersonRoleChips({
    super.key,
    required this.roles,
    required this.onRoles,
  });

  final List<KeyPersonRole> roles;
  final void Function(List<KeyPersonRole> next) onRoles;

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final repCount = roles
        .where((r) =>
            r == KeyPersonRole.director || r == KeyPersonRole.signatory)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Role', style: text.label),
        const SizedBox(height: MyazaSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _repRoles)
              _Chip(
                label: entry.label,
                active: roles.contains(entry.role),
                // Removing the last one would take them out of this section
                // entirely, which is what the card's X is for.
                onTap: roles.contains(entry.role) && repCount <= 1
                    ? null
                    : () => onRoles(
                          roles.contains(entry.role)
                              ? [
                                  for (final r in roles)
                                    if (r != entry.role) r,
                                ]
                              : [...roles, entry.role],
                        ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          // 44pt tall including the padding, so a chip is a comfortable tap.
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primary : Colors.transparent,
            border: Border.all(color: active ? colors.primary : colors.border),
            borderRadius: BorderRadius.circular(MyazaRadius.full),
          ),
          child: Text(
            label,
            style: text.bodyMedium.copyWith(
              color: active ? colors.background : colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
