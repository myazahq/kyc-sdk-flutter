import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// The Copy / Share pill under a row that still owes a check. Split from the
// card (200-line rule).

class KeyPeopleActionPill extends StatelessWidget {
  final MyazaIconData icon;
  final String label;
  final VoidCallback onTap;

  const KeyPeopleActionPill({super.key, 
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    return Material(
      color: colors.primary100,
      borderRadius: BorderRadius.circular(MyazaRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyazaRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MyazaSpacing.sm + 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MyazaIcon(icon, size: 15, color: colors.primary),
              const SizedBox(width: MyazaSpacing.xs + 2),
              Text(
                label,
                style: text.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
