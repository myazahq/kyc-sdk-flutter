import 'package:flutter/material.dart';

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import '../widgets/country_flag.dart';
import '../widgets/icons/icons.dart';

// ─── One saved key person, summarised ────────────────────────────────────────
//
// Monogram avatar with their ID-issuing country flag badged on its corner,
// name, role · ownership meta, and the country + email their invite will go
// to. The whole card opens the edit sheet (the pencil is the affordance);
// removal lives INSIDE that sheet, so a stray tap can never delete a person.
//
// Same visual language as the applicant step's "this is me" tiles, so the two
// screens read as one system. Mirrors the web/RN KeyPersonCard 1:1.

class KeyPersonCard extends StatelessWidget {
  final KeyPersonEntry entry;
  final VoidCallback onTap;

  /// Roles whose email is mandatory (they are sent a verification link) —
  /// threaded from the step so the card and the Continue gate agree on what
  /// "complete" means.
  final Set<KeyPersonRole> emailRequiredFor;

  /// The hat THIS section is about. One person can hold several, so the same
  /// row reads "Beneficial owner" under owners and "Director" under
  /// representatives; the entry's own headline would name only the strongest
  /// and quietly contradict the heading above it.
  final String? roleLabel;

  /// Takes the person out of the section they are being shown in, which is not
  /// the same as deleting them: see [withoutSection]. Absent on a flat list.
  final VoidCallback? onRemove;

  const KeyPersonCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.emailRequiredFor = const {},
    this.roleLabel,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final radius = BorderRadius.circular(MyazaRadius.sm);

    final name = entry.name.trim().isEmpty ? 'Unnamed person' : entry.name.trim();
    final country =
        entry.country.trim().isEmpty ? null : entry.country.trim().toUpperCase();
    final pct = entry.ownershipPct.trim();
    // A row persisted by the old inline UI (or interrupted mid-edit) may be
    // incomplete — the card says so instead of silently blocking Continue. A
    // missing REQUIRED email gets named specifically: "incomplete" on a row
    // whose name, role and country are all filled reads as a bug.
    final incomplete = !entry.isValidWith(emailRequiredFor);
    final problem = rowNeedsEmail(entry, emailRequiredFor) &&
            entry.email.trim().isEmpty &&
            entry.name.trim().length >= 2
        ? 'Email required, tap to add'
        : 'Incomplete, tap to finish';

    final meta = [
      roleLabel ?? entry.role.label,
      if (pct.isNotEmpty) '$pct% ownership',
    ].join(' · ');
    // The flag alone doesn't say WHICH country — spell it out, alongside the
    // email their invite goes to.
    final detail = [
      if (country != null) countryLabel(country),
      if (entry.email.trim().isNotEmpty) entry.email.trim(),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: MyazaSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: radius,
        border: Border.all(
            color: incomplete ? MyazaColors.error : colors.border),
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
                // Monogram avatar with the ID-issuing-country flag badge.
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
                          color: colors.primary100,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initialsOf(name),
                          style: text.bodySmall.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (country != null)
                        Positioned(
                          bottom: -2,
                          right: -4,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: colors.background, width: 2),
                            ),
                            child: ClipOval(
                              child:
                                  MyazaCountryFlag(country: country, size: 16),
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
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textDark)),
                      const SizedBox(height: 2),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              .copyWith(color: colors.textSecondary)),
                      if (incomplete) ...[
                        const SizedBox(height: 2),
                        Text(problem,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                .copyWith(color: MyazaColors.error)),
                      ] else if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                .copyWith(color: colors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: MyazaSpacing.sm),
                MyazaIcon(MyazaIcons.pencil,
                    size: 16, color: colors.textSecondary),
                if (onRemove != null)
                  Padding(
                    padding: const EdgeInsets.only(left: MyazaSpacing.xs),
                    child: IconButton(
                      onPressed: onRemove,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove from this section',
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: MyazaIcon(MyazaIcons.x,
                          size: 16, color: colors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
