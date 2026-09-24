import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../widgets/icons/icons.dart';

/// The keep-or-update question after a pin move.
///
/// A picked address is never silently replaced by a reverse geocode, and never
/// silently kept against the applicant's wishes either: they choose. Rendered
/// on the pin step only while the question is open (`shouldAskLabelDecision`).
/// Mirrors the web and RN SDKs' LabelDecisionRow.
class AddressLabelDecision extends StatelessWidget {
  /// The picked address line under question.
  final String label;
  final VoidCallback onKeep;
  final VoidCallback onAdopt;

  const AddressLabelDecision({
    super.key,
    required this.label,
    required this.onKeep,
    required this.onAdopt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.05),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(MyazaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: MyazaIcon(MyazaIcons.mapPinned,
                    size: 16, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You moved the pin',
                        style:
                            text.label.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    // The line under question is emphasised inside the
                    // sentence: the applicant is choosing between two
                    // addresses, so the one at stake has to be readable at a
                    // glance rather than hidden in body copy.
                    Text.rich(
                      TextSpan(
                        style: text.bodySmall
                            .copyWith(color: colors.textSecondary, height: 1.4),
                        children: [
                          const TextSpan(text: 'Keep '),
                          TextSpan(
                            text: label,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colors.textDark),
                          ),
                          const TextSpan(
                            text: ' as your address, or update it to match the '
                                'new spot?',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyazaSpacing.sm + 4),
          // Indented under the text (web pl-11), and COMPACT: a 36px pair
          // rather than two 48px flow buttons, the same buttons RN draws.
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              children: [
                Expanded(
                  child: _DecisionButton(
                    label: 'Keep this address',
                    primary: true,
                    onTap: onKeep,
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                Expanded(
                  child: _DecisionButton(
                    label: "Use the pin’s address",
                    onTap: onAdopt,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? colors.primary : colors.background,
        borderRadius: BorderRadius.circular(MyazaRadius.xs),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MyazaRadius.xs),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: MyazaSpacing.sm),
            decoration: BoxDecoration(
              border: primary ? null : Border.all(color: colors.primary),
              borderRadius: BorderRadius.circular(MyazaRadius.xs),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: primary ? colors.onPrimary : colors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
