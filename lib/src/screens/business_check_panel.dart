import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/myaza_alert.dart';

// ─── What the register said, when it was NOT a plain yes ─────────────────────
//
// The check is a paid, deliberate step, so it is shown rather than run
// invisibly: the applicant sees a company that is not on the register caught
// HERE instead of after documents and a selfie. Nothing is shown for a company
// that WAS found — the register's answer is already in the form the applicant
// is looking at, editable, and its officers are the next step. `skipped` shows
// nothing on purpose (the organisation could not be charged, which is not the
// applicant's problem and not something they can act on), and `checking` shows
// nothing either — the loader lives inside the Continue button they just
// pressed. Mirrors the web and RN SDKs' BusinessCheckPanel.

class BusinessCheckPanel extends StatelessWidget {
  /// The check's status token, from BusinessCheckState.
  final String status;

  const BusinessCheckPanel({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'not_found') {
      return const MyazaAlert.warning(
        title: 'We could not find this business on the register',
        message: 'Check the registration number and try again.',
      );
    }

    if (status == 'limit_reached') {
      // Not a failure: the submission still runs its own check. What it says
      // is "stop re-picking and look at the number", which is the only thing
      // left that helps.
      return const _NeutralPanel(
        title: 'We have stopped looking this up for now',
        body: 'This application has searched the register several times. '
            'Check the registration number is right; your details will still '
            'be verified when you submit.',
      );
    }

    if (status == 'unavailable') {
      // Deliberately not "we could not find it": an outage is not evidence
      // that a business is unregistered.
      return const _NeutralPanel(
        title: 'The register is temporarily unavailable',
        body: 'You can continue, and we will check it shortly.',
      );
    }

    return const SizedBox.shrink();
  }
}

class _NeutralPanel extends StatelessWidget {
  final String title;
  final String body;

  const _NeutralPanel({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.all(MyazaSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(MyazaRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.label),
          const SizedBox(height: 2),
          Text(body,
              style: text.bodySmall.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}
