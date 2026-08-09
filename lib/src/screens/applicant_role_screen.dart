import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/theme.dart';
import '../providers/kyc_provider.dart';
import '../widgets/country_flag.dart';
import '../widgets/dashed_border.dart';
import '../widgets/myaza_button.dart';
import '../widgets/myaza_input.dart';
import '../widgets/myaza_select.dart';

// ─── Applicant role screen ────────────────────────────────────────────────────
//
// "Now verify your own identity": the person submitting the KYB application
// declares who they are, then runs the ORDINARY individual capture leg for
// their own identity.
//
// When key people were entered earlier, the applicant may BE one of them — so
// the screen first asks "which of these is you?" (pre-selected when the
// consumer's userData name matches). Picking themselves flags that entry on
// the submission and the server merges the two records: one person, one KYC,
// one screening, no duplicate invite. "I'm not one of these" falls through to
// the plain role + name form. Mirrors the web SDK's ApplicantRoleStep.

class ApplicantRoleScreen extends ConsumerStatefulWidget {
  const ApplicantRoleScreen({super.key});

  @override
  ConsumerState<ApplicantRoleScreen> createState() =>
      _ApplicantRoleScreenState();
}

/// Local tri-state: a person's index, "someone else", or nothing chosen yet.
sealed class _Selection {
  const _Selection();
}

class _SelectionPerson extends _Selection {
  final int index;
  const _SelectionPerson(this.index);
}

class _SelectionOther extends _Selection {
  const _SelectionOther();
}

class _ApplicantRoleScreenState extends ConsumerState<ApplicantRoleScreen> {
  final _nameCtrl = TextEditingController();
  ApplicantRole? _role;
  _Selection? _selection;

  /// Valid entered people with their ORIGINAL index — the payload flag is
  /// index-based, so the list and the submission can never disagree.
  List<(int, KeyPersonEntry)> get _people {
    final rows = ref.read(kYCNotifierProvider).keyPeople;
    return [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].isValid) (i, rows[i]),
    ];
  }

  @override
  void initState() {
    super.initState();
    final s = ref.read(kYCNotifierProvider);
    _role = s.applicantRole;
    final config = ref.read(kycConfigProvider);
    final prop = [config.userData?.firstName, config.userData?.lastName]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .join(' ');
    _nameCtrl.text = s.applicantName ?? prop;

    // Stored choice wins; first arrival pre-selects the applicant's own entry
    // when the userData name matches (they still confirm explicitly).
    if (s.applicantKeyPersonIndex != null) {
      _selection = _SelectionPerson(s.applicantKeyPersonIndex!);
    } else if (s.applicantRole != null) {
      _selection = const _SelectionOther();
    } else if (prop.isNotEmpty) {
      for (final (index, row) in _people) {
        if (namesLooselyMatch(prop, row.name)) {
          _selection = _SelectionPerson(index);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final selection = _selection;
    if (selection is _SelectionPerson) {
      final rows = ref.read(kYCNotifierProvider).keyPeople;
      if (selection.index >= rows.length) return;
      final person = rows[selection.index];
      // KeyPersonRole is a strict subset of ApplicantRole — map by name.
      final role = ApplicantRole.values.byName(person.role.name);
      notifier.setApplicant(
        role: role,
        name: person.name.trim(),
        keyPersonIndex: selection.index,
      );
      // Their entry already answered "where was your ID issued?" — the leg
      // uses that country and the country-select step is skipped (see
      // buildStepOrder's applicantSelfCountry guard).
      final country = person.country.trim();
      if (country.isNotEmpty) notifier.setCountry(country.toUpperCase());
    } else {
      final role = _role;
      if (role == null) return;
      final name = _nameCtrl.text.trim();
      notifier.setApplicant(role: role, name: name.isEmpty ? null : name);
    }
    notifier.nextStep();
  }

  bool get _canContinue {
    if (_people.isEmpty) return _role != null;
    final selection = _selection;
    if (selection is _SelectionPerson) return true;
    return selection is _SelectionOther && _role != null;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final people = _people;
    final showRoleForm = people.isEmpty || _selection is _SelectionOther;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(MyazaSpacing.md),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(MyazaRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary100,
                  borderRadius: BorderRadius.circular(MyazaRadius.sm),
                ),
                child: Icon(LucideIcons.scanFace,
                    size: 18, color: colors.primary),
              ),
              const SizedBox(width: MyazaSpacing.md),
              Expanded(
                child: Text(
                  'Regulations require the person submitting a business '
                  'application to verify their own identity. This only takes '
                  'a minute.',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MyazaSpacing.lg),

        if (people.isNotEmpty) ...[
          Text('Are you one of the people you listed?', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          for (final (index, row) in people) ...[
            _SelfTile(
              label: row.name.trim(),
              sublabel: row.ownershipPct.trim().isNotEmpty
                  ? '${row.role.label} · ${row.ownershipPct.trim()}% ownership'
                  : row.role.label,
              countryCode:
                  row.country.trim().isNotEmpty ? row.country.trim().toUpperCase() : null,
              isSelected: _selection is _SelectionPerson &&
                  (_selection as _SelectionPerson).index == index,
              onTap: () => setState(() => _selection = _SelectionPerson(index)),
            ),
            const SizedBox(height: MyazaSpacing.sm),
          ],
          _SelfTile(
            label: "I'm not one of these people",
            other: true,
            isSelected: _selection is _SelectionOther,
            onTap: () => setState(() => _selection = const _SelectionOther()),
          ),
          if (_selection is _SelectionPerson) ...[
            const SizedBox(height: MyazaSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyazaSpacing.sm + 4,
                vertical: MyazaSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: colors.primary100,
                borderRadius: BorderRadius.circular(MyazaRadius.xs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child:
                        Icon(LucideIcons.check, size: 14, color: colors.primary),
                  ),
                  const SizedBox(width: MyazaSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      "You'll verify your identity at the end of this form — "
                      'no separate invite link is needed for you.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: MyazaSpacing.md),
        ],

        if (showRoleForm) ...[
          Text('Your role at the business', style: text.label),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaSelect<ApplicantRole>(
            value: _role,
            hint: 'Select your role',
            sheetTitle: 'Your role',
            options: [
              for (final role in ApplicantRole.values)
                MyazaSelectOption(value: role, label: role.label),
            ],
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: MyazaSpacing.md),

          Text.rich(TextSpan(children: [
            TextSpan(text: 'Full name', style: text.label),
            TextSpan(
              text: ' (optional)',
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ])),
          const SizedBox(height: MyazaSpacing.xs),
          MyazaInput(
            controller: _nameCtrl,
            hint: 'Enter your full name',
            // It's a person's name — start every word capitalized.
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ],

        const SizedBox(height: MyazaSpacing.xl),
        MyazaButton(
          label: 'Continue',
          onPressed: _canContinue ? _onContinue : null,
        ),
      ],
    );
  }
}

/// "Richard Ingwe" → "RI" — the avatar monogram.
String _initialsOf(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((t) => t.isEmpty ? '' : t[0].toUpperCase())
    .join();

/// One selectable "this is me" card — monogram avatar with the person's
/// ID-issuing-country flag badged on its corner, name + role/ownership, and a
/// radio dot. The "someone else" variant swaps the avatar for an add-person
/// icon on a dashed border. Mirrors the web SDK's ApplicantRoleStep cards 1:1.
class _SelfTile extends StatelessWidget {
  final String label;
  final String? sublabel;
  final String? countryCode;

  /// The dashed "I'm not one of these people" variant.
  final bool other;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelfTile({
    required this.label,
    this.sublabel,
    this.countryCode,
    this.other = false,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final radius = BorderRadius.circular(MyazaRadius.sm);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary50 : colors.background,
        borderRadius: radius,
        // The dashed "someone else" border is painted by the wrapper below;
        // a solid border everywhere else.
        border: other && !isSelected
            ? null
            : Border.all(
                color: isSelected ? colors.primary : colors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(MyazaSpacing.md - 2),
            child: Row(
              children: [
                // Monogram avatar (or the add-person icon) with the flag badge.
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: other && !isSelected
                              ? colors.backgroundSecondary
                              : colors.primary100,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: other
                            ? Icon(LucideIcons.userRoundPlus,
                                size: 18,
                                color: isSelected
                                    ? colors.primary
                                    : colors.textSecondary)
                            : Text(
                                _initialsOf(label),
                                style: text.bodySmall.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      if (countryCode != null)
                        Positioned(
                          bottom: -2,
                          right: -4,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? colors.primary50
                                    : colors.background,
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: MyazaCountryFlag(
                                  country: countryCode, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                      if (sublabel != null) ...[
                        const SizedBox(height: 2),
                        Text(sublabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                .copyWith(color: colors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                // Radio dot — filled with a check when selected.
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? colors.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? colors.primary : colors.border,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(LucideIcons.check,
                          size: 12, color: colors.background)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (other && !isSelected) {
      return CustomPaint(
        painter: DashedRoundedBorder(
          color: colors.border,
          radius: MyazaRadius.sm,
        ),
        child: card,
      );
    }
    return card;
  }
}
