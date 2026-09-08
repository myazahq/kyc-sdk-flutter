import 'biometric_options.dart';
import 'copy_tokens.dart';
import 'kyc_config.dart';
import 'scope.dart';

// ─── The org's copy on the biometric screens ────────────────────────────────
//
// The builder's "Face check screens" fields (user decision 2026-09-07): the
// org's own words for the loading screen and the two verdict screens of a
// biometric flow. `waiting` is the ONE loading screen from the shutter to the
// verdict, on both scopes; `verified` and `declined` are the in-flow verdict
// screens, so they apply to a re-authentication only (publish refuses them on
// enrolment, which shows no verdict). A `declined` description wins over the
// server's reason: the org chose to say that. Mirrors the server's
// WorkflowBiometricCopySchema and the web/RN SDKs' BiometricCopy; keep the
// four in lockstep.

/// One screen's words. A null (or blank) field means the SDK default shows.
class BiometricCopyText {
  final String? title;
  final String? description;
  const BiometricCopyText({this.title, this.description});

  factory BiometricCopyText.fromJson(Map<String, dynamic> json) => BiometricCopyText(
        title: _text(json['title']),
        description: _text(json['description']),
      );

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  BiometricCopyText merge(BiometricCopyText? over) => over == null
      ? this
      : BiometricCopyText(
          title: over.title ?? title,
          description: over.description ?? description,
        );

  bool get isEmpty => title == null && description == null;
}

class BiometricCopy {
  final BiometricCopyText? waiting;
  final BiometricCopyText? verified;
  final BiometricCopyText? declined;
  const BiometricCopy({this.waiting, this.verified, this.declined});

  factory BiometricCopy.fromJson(Map<String, dynamic> json) => BiometricCopy(
        waiting: _screen(json['waiting']),
        verified: _screen(json['verified']),
        declined: _screen(json['declined']),
      );

  static BiometricCopyText? _screen(Object? v) =>
      v is Map ? BiometricCopyText.fromJson(v.cast<String, dynamic>()) : null;

  /// Per screen, then per field: a flow that words only the loading screen
  /// keeps a host's verdict copy.
  BiometricCopy merge(BiometricCopy? over) => over == null
      ? this
      : BiometricCopy(
          waiting: (waiting ?? const BiometricCopyText()).merge(over.waiting),
          verified: (verified ?? const BiometricCopyText()).merge(over.verified),
          declined: (declined ?? const BiometricCopyText()).merge(over.declined),
        );
}

/// The copy ready to render: tokens filled, a field that emptied out treated
/// as absent (the default shows rather than a blank title), and every screen
/// null off the biometric scopes, where the block never applies. The screens
/// hand each entry to describeWaiting / describeOutcome as an override.
class ResolvedBiometricCopy {
  final BiometricCopyText? waiting;
  final BiometricCopyText? verified;
  final BiometricCopyText? declined;
  const ResolvedBiometricCopy({this.waiting, this.verified, this.declined});

  static const none = ResolvedBiometricCopy();
}

ResolvedBiometricCopy biometricCopyFor({
  String? scope,
  BiometricFlowConfig? biometric,
  String? firstName,
  String? lastName,
}) {
  final resolved = configScope(scope);
  if (resolved != 'biometric-authentication' && resolved != 'biometric-enrollment') {
    return ResolvedBiometricCopy.none;
  }
  final copy = biometric?.copy;
  if (copy == null) return ResolvedBiometricCopy.none;

  BiometricCopyText? fill(BiometricCopyText? text) {
    if (text == null) return null;
    final title = text.title == null
        ? ''
        : fillCopyTokens(text.title!, firstName: firstName, lastName: lastName);
    final description = text.description == null
        ? ''
        : fillCopyTokens(text.description!, firstName: firstName, lastName: lastName);
    final out = BiometricCopyText(
      title: title.isEmpty ? null : title,
      description: description.isEmpty ? null : description,
    );
    return out.isEmpty ? null : out;
  }

  final auth = resolved == 'biometric-authentication';
  return ResolvedBiometricCopy(
    waiting: fill(copy.waiting),
    // Enrolment shows no verdict, so a stray key there has no screen to land on.
    verified: auth ? fill(copy.verified) : null,
    declined: auth ? fill(copy.declined) : null,
  );
}

/// The same question asked of a whole config.
extension BiometricCopyX on MyazaKYCConfig {
  ResolvedBiometricCopy get biometricCopy => biometricCopyFor(
        scope: scope,
        biometric: biometric,
        firstName: userData?.firstName,
        lastName: userData?.lastName,
      );
}
