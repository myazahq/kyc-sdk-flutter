import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/dashed_border.dart';
import '../widgets/myaza_button.dart';
import 'key_person_card.dart';
import 'key_person_sheet.dart';

// ─── Business key-people screen ───────────────────────────────────────────────
//
// "Directors & owners": the applicant lists the company's directors and 25%+
// owners. Skippable when the workflow sets no minimum (the registry lookup
// fills the gaps). The list stays a clean stack of compact summary cards; the
// FORM lives in the add/edit sheet (key_person_sheet.dart). Tapping a card
// edits it; removal is inside the edit sheet, behind a deliberate tap — never
// one stray touch on the list.
//
// Mirrors the web SDK's BusinessKeyPeopleStep and the RN screen 1:1.

class BusinessKeyPeopleScreen extends ConsumerWidget {
  const BusinessKeyPeopleScreen({super.key});

  double _pctOf(KeyPersonEntry row) => row.ownershipValue ?? 0;

  String _fmtPct(double n) =>
      n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref, {
    int? index,
  }) async {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final state = ref.read(kYCNotifierProvider);
    final rows = state.keyPeople;
    // New people default to the business's registry country (picked on the
    // details step) — most directors are local, and a foreign one just
    // switches theirs.
    final defaultCountry = state.businessCountry ??
        ref.read(kycConfigProvider).business?.country ??
        '';
    final editing = index != null;
    final initial = editing
        ? rows[index]
        : KeyPersonEntry(country: defaultCountry);
    final totalPct = rows.fold<double>(0, (sum, r) => sum + _pctOf(r));

    final result = await showKeyPersonSheet(
      context,
      editing: editing,
      initial: initial,
      uboThreshold: ref
              .read(kycConfigProvider)
              .business
              ?.keyPeople
              ?.ownershipThreshold ??
          25,
      otherPctTotal: editing ? totalPct - _pctOf(initial) : totalPct,
    );
    if (result == null) return;

    final current = ref.read(kYCNotifierProvider).keyPeople;
    switch (result) {
      case KeyPersonSaved(:final entry):
        notifier.setKeyPeople(editing
            ? [
                for (var i = 0; i < current.length; i++)
                  i == index ? entry : current[i],
              ]
            : [...current, entry]);
      case KeyPersonRemoved():
        notifier.setKeyPeople([
          for (var i = 0; i < current.length; i++)
            if (i != index) current[i],
        ]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final rows = ref.watch(kYCNotifierProvider.select((s) => s.keyPeople));
    final minEntries =
        keyPeopleMinEntries(ref.watch(kycConfigProvider).business);

    final validCount = rows.where((r) => r.isValid).length;
    final hasInvalid = rows.any((r) => !r.isBlank && !r.isValid);
    final meetsMinimum = validCount >= minEntries;

    // Combined ownership above 100% is factually impossible — catch the typo
    // here rather than shipping it into the registry cross-check as a doomed
    // mismatch. Under 100% is fine (not every owner has to be listed).
    final totalPct = rows.fold<double>(0, (sum, r) => sum + _pctOf(r));
    final overAllocated = totalPct > 100;

    final visible = [
      for (var i = 0; i < rows.length; i++)
        if (!rows[i].isBlank) i,
    ];

    void onContinue() {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      // Half-typed rows are dropped rather than submitted: an entry the user
      // abandoned is not a person they disclosed.
      notifier.setKeyPeople(
          rows.where((r) => r.isValid).toList(growable: false));
      notifier.nextStep();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No lead paragraph: the step HEADER carries "List the company's
        // directors and owners of 25% or more…" (myaza_kyc_widget.dart step
        // meta, matching the web SDK's StepHeader).
        if (rows.isEmpty && minEntries == 0)
          _HintBox(
            child: Text(
              "You can skip this if you're unsure — we'll identify directors "
              'and owners from the official registry. Adding them here speeds '
              'up the review.',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          )
        else if (minEntries > 0 && validCount < minEntries)
          _HintBox(
            child: Text(
              'List at least $minEntries '
              '${minEntries == 1 ? 'person' : 'people'} to continue'
              '${validCount > 0 ? ' ($validCount of $minEntries added)' : ''}.',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        if (rows.isEmpty || (minEntries > 0 && validCount < minEntries))
          const SizedBox(height: MyazaSpacing.md),

        for (final i in visible)
          KeyPersonCard(
            entry: rows[i],
            onTap: () => _openSheet(context, ref, index: i),
          ),
        // The cards and the add affordance are different things — give the
        // boundary some air (cards already carry a small bottom margin).
        if (visible.isNotEmpty) const SizedBox(height: MyazaSpacing.sm),

        if (rows.length < kMaxKeyPeopleRows)
          MyazaButton.outline(
            label: 'Add a person',
            leadingIcon: const Icon(LucideIcons.userRoundPlus, size: 18),
            onPressed: () => _openSheet(context, ref),
          )
        else
          Text(
            'You can list up to $kMaxKeyPeopleRows people here.',
            textAlign: TextAlign.center,
            style: text.bodySmall.copyWith(color: colors.textMuted),
          ),
        const SizedBox(height: MyazaSpacing.md),

        // Total-ownership summary at the DECISION point — the disabled
        // Continue button always explains itself, wherever the offending
        // card is.
        if (totalPct > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyazaSpacing.md,
              vertical: MyazaSpacing.sm + 4,
            ),
            decoration: BoxDecoration(
              color:
                  overAllocated ? colors.errorBg : colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(MyazaRadius.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total ownership listed',
                  style: text.bodySmall.copyWith(
                    color: overAllocated
                        ? MyazaColors.error
                        : colors.textSecondary,
                  ),
                ),
                Text(
                  '${_fmtPct(totalPct)}%',
                  style: text.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        overAllocated ? MyazaColors.error : colors.textDark,
                  ),
                ),
              ],
            ),
          ),
          if (overAllocated) ...[
            const SizedBox(height: MyazaSpacing.xs),
            Text(
              "Together the percentages can't exceed 100% — reduce them by "
              '${_fmtPct(totalPct - 100)}%.',
              style: text.bodySmall.copyWith(color: MyazaColors.error),
            ),
          ],
        ],
        const SizedBox(height: MyazaSpacing.md),
        MyazaButton(
          label: 'Continue',
          onPressed: meetsMinimum && !hasInvalid && !overAllocated
              ? onContinue
              : null,
        ),
      ],
    );
  }
}

class _HintBox extends StatelessWidget {
  final Widget child;
  const _HintBox({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // DASHED, matching the web SDK's `border-dashed` hint card (and the RN
    // SDK's) — rounded-xl (12) + p-4, via the shared painter.
    return CustomPaint(
      painter: DashedRoundedBorder(
        color: colors.border,
        radius: MyazaRadius.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(MyazaSpacing.md),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(MyazaRadius.sm),
        ),
        child: child,
      ),
    );
  }
}
