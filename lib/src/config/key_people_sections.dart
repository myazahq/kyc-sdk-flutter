import 'business.dart';
import 'business_application.dart';

/// The sectioned key-people model: UBOs / Shareholders / Directors &
/// representatives as VIEWS over one shared list of people.
///
/// A section is not a bucket. One human is a director AND a 30% owner, and the
/// register files them that way, so an entry appears in every section whose
/// definition it meets: membership is derived from the roles it holds and the
/// stake it declares, never stored. Quick-add grants an existing person another
/// hat instead of retyping them; classification by ownership happens here
/// exactly as the server escalates it, so the screen never disagrees with what
/// the submission will be read as.
///
/// The Dart port of the RN SDK's config/keyPeopleSections.ts, which mirrors the
/// web SDK's. Three copies of one rule: change it in all three, or a person
/// lands in a different section depending on which SDK they walked.
enum KeyPeopleSection { ubos, shareholders, representatives }

/// Strongest first: the headline role on one-role surfaces. Mirrors the
/// server's precedence in `key-people/roles.ts`; keep the two in lockstep.
const List<KeyPersonRole> kRolePrecedence = [
  KeyPersonRole.beneficialOwner,
  KeyPersonRole.director,
  KeyPersonRole.signatory,
  KeyPersonRole.shareholder,
];

KeyPersonRole primaryRole(List<KeyPersonRole> roles) {
  for (final role in kRolePrecedence) {
    if (roles.contains(role)) return role;
  }
  return KeyPersonRole.shareholder;
}

/// The roles an entry actually holds; falls back to the headline for rows
/// minted before `roles` existed (restored sessions).
List<KeyPersonRole> rolesOf(KeyPersonEntry entry) =>
    entry.roles.isNotEmpty ? entry.roles : [entry.role];

/// The declared stake, or null when blank or unparseable.
double? stakeOf(KeyPersonEntry entry) => entry.ownershipValue;

/// The role a section's add tile (and quick-add chip) grants.
const Map<KeyPeopleSection, KeyPersonRole> kSectionRole = {
  KeyPeopleSection.ubos: KeyPersonRole.beneficialOwner,
  KeyPeopleSection.shareholders: KeyPersonRole.shareholder,
  KeyPeopleSection.representatives: KeyPersonRole.director,
};

/// Which sections this entry belongs to.
///
/// - UBOs: a natural person holding the beneficial-owner role OR a stake at or
///   above the threshold, the same escalation the server performs, so a
///   shareholder who types 60% moves up on screen exactly as they will in the
///   submission. A company never qualifies (a beneficial owner is a natural
///   person in every regime that defines one).
/// - Shareholders: every corporate holder whatever its stake (the
///   never-a-UBO rule made visible), plus people with a declared holding or
///   shareholder role below the threshold. A person the UBO section claimed is
///   not ALSO a plain shareholder: same stake, one classification.
/// - Representatives: anyone holding director or signatory.
Set<KeyPeopleSection> sectionsFor(KeyPersonEntry entry, double threshold) {
  final roles = rolesOf(entry);
  final stake = stakeOf(entry);
  final out = <KeyPeopleSection>{};

  final isUbo = !entry.isCorporate &&
      (roles.contains(KeyPersonRole.beneficialOwner) ||
          (stake != null && stake >= threshold));
  if (isUbo) out.add(KeyPeopleSection.ubos);

  if (entry.isCorporate ||
      (!isUbo &&
          (roles.contains(KeyPersonRole.shareholder) ||
              (stake != null && stake > 0)))) {
    out.add(KeyPeopleSection.shareholders);
  }

  if (roles.contains(KeyPersonRole.director) ||
      roles.contains(KeyPersonRole.signatory)) {
    out.add(KeyPeopleSection.representatives);
  }
  return out;
}

/// Indices of the entries each section shows, in list order.
Map<KeyPeopleSection, List<int>> sectionMembers(
  List<KeyPersonEntry> rows,
  double threshold,
) {
  final out = {
    for (final section in KeyPeopleSection.values) section: <int>[],
  };
  for (var i = 0; i < rows.length; i++) {
    for (final section in sectionsFor(rows[i], threshold)) {
      out[section]!.add(i);
    }
  }
  return out;
}

/// Entries offerable as quick-add chips for a section: already entered, named,
/// not yet a member, and eligible (a company can never be quick-added as a
/// UBO). One tap grants the section's role.
List<int> quickAddCandidates(
  List<KeyPersonEntry> rows,
  KeyPeopleSection section,
  double threshold,
) {
  final members = sectionMembers(rows, threshold)[section]!.toSet();
  final out = <int>[];
  for (var i = 0; i < rows.length; i++) {
    if (members.contains(i)) continue;
    if (rows[i].name.trim().length < 2) continue;
    if (section == KeyPeopleSection.ubos && rows[i].isCorporate) continue;
    // Only offer a chip that would DO something. Membership is derived, so
    // granting a role does not always produce it: a beneficial owner is not
    // also a plain shareholder (same stake, one classification), so offering
    // them under Shareholders gave a chip that could be tapped forever and
    // never move anybody. An affordance that does nothing is worse than an
    // absent one, because the applicant concludes the app is broken.
    if (!sectionsFor(grantRole(rows[i], section), threshold).contains(section)) {
      continue;
    }
    out.add(i);
  }
  return out;
}

/// Grant an entry another hat (quick-add). The headline follows precedence.
KeyPersonEntry grantRole(KeyPersonEntry entry, KeyPeopleSection section) {
  final roles = rolesOf(entry);
  final granted = kSectionRole[section]!;
  final next = roles.contains(granted) ? roles : [...roles, granted];
  return entry.copyWith(roles: next, role: primaryRole(next));
}

/// Take an entry out of a section (the card's X).
///
/// Dropping the section's roles is enough when membership came from them; when
/// it came from a declared stake, or nothing else keeps the row alive, the
/// honest reading of "remove from UBOs" is "remove this person". Null says so,
/// and the caller deletes the row.
KeyPersonEntry? withoutSection(
  KeyPersonEntry entry,
  KeyPeopleSection section,
  double threshold,
) {
  final dropped = section == KeyPeopleSection.representatives
      ? [KeyPersonRole.director, KeyPersonRole.signatory]
      : [kSectionRole[section]!];
  final remaining =
      rolesOf(entry).where((r) => !dropped.contains(r)).toList(growable: false);
  if (remaining.isEmpty) return null;
  final next = entry.copyWith(roles: remaining, role: primaryRole(remaining));
  // Still a member by stake? Then dropping the role did not remove them, and
  // the tap meant more than that.
  if (sectionsFor(next, threshold).contains(section)) return null;
  return next;
}
