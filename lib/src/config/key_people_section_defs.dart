import 'business.dart';
import 'key_people_sections.dart';

// The step's section definitions: which sections show and what they say.
// Split from key_people_sections.dart (200-line rule), as the RN SDK splits
// keyPeopleSectionDefs.ts from keyPeopleSections.ts.

/// The register's default beneficial-ownership line, when the workflow does not
/// set its own. Mirrors the server's `uboThresholdFor`: 25 is the
/// FATF/EU/FinCEN indicative figure; Nigeria's CAMA files significant control
/// from a lower bar, so NG defaults to 10. Keep in lockstep with the web and RN
/// SDKs.
double defaultUboThreshold(String? country) =>
    (country ?? '').toUpperCase() == 'NG' ? 10 : 25;

class KeyPeopleSectionDef {
  const KeyPeopleSectionDef({
    required this.key,
    required this.title,
    required this.description,
    required this.addLabel,
  });

  final KeyPeopleSection key;
  final String title;
  final String description;
  final String addLabel;
}

/// A threshold as a person would write it: 25, not 25.0.
String _pct(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toString();

/// Which sections the step shows, with their plain-language definitions.
///
/// The definitions carry the REAL threshold (workflow override or the
/// register's default): a printed band the server does not enforce would be a
/// lie the applicant plans around. Scope follows the workflow's
/// `keyPeople.roles`.
List<KeyPeopleSectionDef> keyPeopleSectionList(
  WorkflowBusinessConfig? business,
  double threshold,
) {
  final scoped = business?.keyPeople?.roles ?? const <KeyPersonRole>[];
  bool inScope(List<KeyPersonRole> roles) =>
      scoped.isEmpty || roles.any(scoped.contains);

  final t = _pct(threshold);
  final out = <KeyPeopleSectionDef>[];

  if (inScope(const [KeyPersonRole.beneficialOwner])) {
    out.add(KeyPeopleSectionDef(
      key: KeyPeopleSection.ubos,
      title: 'Beneficial owners',
      description: 'Individuals who own $t% or more of the company.',
      addLabel: 'Add a beneficial owner',
    ));
  }
  if (inScope(const [KeyPersonRole.shareholder])) {
    out.add(KeyPeopleSectionDef(
      key: KeyPeopleSection.shareholders,
      title: 'Shareholders',
      description: 'People or companies holding under $t%.',
      addLabel: 'Add a shareholder',
    ));
  }
  if (inScope(const [KeyPersonRole.director, KeyPersonRole.signatory])) {
    out.add(const KeyPeopleSectionDef(
      key: KeyPeopleSection.representatives,
      title: 'Directors & representatives',
      description: 'People who act on behalf of the company.',
      addLabel: 'Add a representative',
    ));
  }
  return out;
}
