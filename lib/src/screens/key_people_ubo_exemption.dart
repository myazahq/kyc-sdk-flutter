import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';

/// The FATF fallback, attested.
///
/// Some companies genuinely have no natural person who qualifies as a UBO —
/// listed companies, complex trusts, nominee arrangements. Without this box the
/// applicant's only moves were to stall or to invent one, and inventing one is
/// worse than the gap it fills.
///
/// It is an ATTESTATION the org can branch on (`keyPeople.uboUnidentifiable`),
/// never a verdict: the registry lookup still says whatever it says, and the
/// applicant's own verification still identifies a senior person.
///
/// Disabled the moment a UBO is listed, because the two claims contradict each
/// other and the applicant should not be able to assert both.
///
/// Mirrors the web and RN SDKs' KeyPeopleUboExemption.
class KeyPeopleUboExemption extends StatelessWidget {
  const KeyPeopleUboExemption({
    super.key,
    required this.checked,
    required this.hasUbos,
    required this.onChanged,
  });

  final bool checked;

  /// A beneficial owner is already listed, so the exemption cannot apply.
  final bool hasUbos;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;

    return Padding(
      padding: const EdgeInsets.only(top: MyazaSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            checked: checked,
            enabled: !hasUbos,
            child: Opacity(
              opacity: hasUbos ? 0.5 : 1,
              child: InkWell(
                onTap: hasUbos ? null : () => onChanged(!checked),
                borderRadius: BorderRadius.circular(MyazaRadius.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: checked ? colors.primary : colors.border,
                          width: 1.5,
                        ),
                        color: checked ? colors.primary : Colors.transparent,
                      ),
                      child: checked
                          ? MyazaIcon(MyazaIcons.check,
                              size: 13, color: colors.onPrimary)
                          : null,
                    ),
                    const SizedBox(width: MyazaSpacing.sm + 4),
                    Expanded(
                      child: Text(
                        'UBOs cannot be identified due to public share '
                        'structures, complex trusts or nominee arrangements.',
                        style:
                            text.bodyMedium.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (checked && !hasUbos)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 32),
              child: Text(
                'We will record this with the application; a senior person is '
                "still identified through the applicant's own verification.",
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
