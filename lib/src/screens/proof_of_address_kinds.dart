import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/proof_of_address.dart';
import '../config/theme.dart';
import '../widgets/check_card.dart';

// ─── Proof of Address — the document kinds, listed ────────────────────────────
//
// The kinds LISTED OUT as the questionnaire's multi-select cards (a square
// check, primary when picked, an icon beside the label) rather than hidden
// behind a select — the options are the information (user decision
// 2026-09-05). ONE kind is picked, because one document is uploaded: the
// cards are radios wearing the multi-select's square check. Locked once a
// file is attached, so the kind cannot drift from the document already
// uploaded. Mirrors the web SDK's steps/PoaDocumentTypeList and the RN twin.

/// One glyph per kind — the SAME Lucide names the web and RN maps carry.
IconData poaTypeIcon(PoaDocumentType type) => switch (type) {
      PoaDocumentType.utilityBill => LucideIcons.zap,
      PoaDocumentType.bankStatement => LucideIcons.landmark,
      PoaDocumentType.tenancyAgreement => LucideIcons.house,
      PoaDocumentType.governmentDocument => LucideIcons.stamp,
      PoaDocumentType.other => LucideIcons.fileText,
    };

class PoaDocumentTypeList extends StatelessWidget {
  final List<PoaDocumentType> options;
  final PoaDocumentType? value;
  final bool enabled;
  final String Function(PoaDocumentType) labelFor;
  final ValueChanged<PoaDocumentType> onChanged;

  const PoaDocumentTypeList({
    super.key,
    required this.options,
    required this.value,
    required this.labelFor,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in options) ...[
          MyazaCheckCard(
            label: labelFor(t),
            checked: t == value,
            icon: poaTypeIcon(t),
            enabled: enabled,
            onTap: () => onChanged(t),
          ),
          if (t != options.last) const SizedBox(height: MyazaSpacing.sm),
        ],
      ],
    );
  }
}
